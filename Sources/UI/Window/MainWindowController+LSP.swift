// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+LSP.swift - Wires local LSP sessions into editor panels.

import Foundation

extension MainWindowController {
    func wireEditorLSPIfNeeded(editorView: EditorView, fileURL: URL?, tabID: TabID?) {
        detachEditorLSP(editorView)

        guard let fileURL,
              let tabID,
              let server = LSPLanguageRegistry.defaults.server(forFileURL: fileURL),
              let snapshot = editorView.lspDocumentSnapshot(languageID: server.languageID),
              let coordinator = lspWorkspaceCoordinator(for: tabID) else {
            return
        }

        coordinator.onDocumentEvent = { [weak self] uri, event in
            DispatchQueue.main.async {
                self?.lspEditorViewsByDocumentURI[uri]?.value?.applyLSPClientEvent(event)
            }
        }
        do {
            _ = try coordinator.openDocument(fileURL: fileURL, snapshot: snapshot)
            lspEditorViewsByDocumentURI[snapshot.uri] = WeakReference(editorView)
            lspDocumentTabIDs[snapshot.uri] = tabID
            enableEditorLSP(editorView, coordinator: coordinator, uri: snapshot.uri)
        } catch {
            disableEditorLSP(editorView)
        }
    }

    func closeEditorLSPIfNeeded(editorView: EditorView, tabID: TabID?) {
        detachEditorLSP(editorView)
    }

    func resetLSPWorkspaceCoordinators() {
        for reference in lspEditorViewsByDocumentURI.values {
            if let editorView = reference.value {
                disableEditorLSP(editorView)
            }
        }
        for coordinator in lspWorkspaceCoordinators.values {
            coordinator.stopAll()
        }
        lspWorkspaceCoordinators.removeAll()
        lspEditorViewsByDocumentURI.removeAll()
        lspDocumentTabIDs.removeAll()
    }

    private func lspWorkspaceCoordinator(for tabID: TabID) -> LSPWorkspaceCoordinator? {
        let config = effectiveConfig(for: tabID)
        guard config.lsp.enabled else {
            return nil
        }
        if let coordinator = lspWorkspaceCoordinators[tabID] {
            return coordinator
        }
        guard let workingDirectory = tabManager.tab(for: tabID)?.workingDirectory else {
            return nil
        }

        let manager = LSPManager(
            registry: .defaults,
            configuration: config.lsp.managerConfiguration,
            discovery: lspServerDiscoveryFactory(),
            processFactory: lspProcessFactory
        )
        let coordinator = LSPWorkspaceCoordinator(
            manager: manager,
            workspaceURL: workingDirectory,
            processID: Int(ProcessInfo.processInfo.processIdentifier)
        )
        lspWorkspaceCoordinators[tabID] = coordinator
        return coordinator
    }

    private func enableEditorLSP(
        _ editorView: EditorView,
        coordinator: LSPWorkspaceCoordinator,
        uri: String
    ) {
        editorView.onLSPHoverRequested = { [weak coordinator] position in
            _ = try? coordinator?.requestHover(uri: uri, position: position)
        }
        editorView.onLSPCompletionRequested = { [weak coordinator] position in
            _ = try? coordinator?.requestCompletion(uri: uri, position: position)
        }
        editorView.onLSPDefinitionRequested = { [weak coordinator] position in
            _ = try? coordinator?.requestDefinition(uri: uri, position: position)
        }
        editorView.onLSPReferencesRequested = { [weak coordinator] position in
            _ = try? coordinator?.requestReferences(uri: uri, position: position)
        }
        editorView.setLSPControlsEnabled(true)
    }

    private func disableEditorLSP(_ editorView: EditorView) {
        editorView.onLSPHoverRequested = nil
        editorView.onLSPCompletionRequested = nil
        editorView.onLSPDefinitionRequested = nil
        editorView.onLSPReferencesRequested = nil
        editorView.setLSPControlsEnabled(false)
    }

    private func detachEditorLSP(_ editorView: EditorView) {
        disableEditorLSP(editorView)

        let documentURIs = lspEditorViewsByDocumentURI.compactMap { uri, reference in
            if reference.value == nil || reference.value === editorView {
                return uri
            }
            return nil
        }

        for uri in documentURIs {
            if let tabID = lspDocumentTabIDs[uri],
               let coordinator = lspWorkspaceCoordinators[tabID] {
                coordinator.closeDocument(uri: uri)
                if coordinator.activeLanguageIDs.isEmpty {
                    lspWorkspaceCoordinators.removeValue(forKey: tabID)
                }
            }
            lspEditorViewsByDocumentURI.removeValue(forKey: uri)
            lspDocumentTabIDs.removeValue(forKey: uri)
        }
    }
}
