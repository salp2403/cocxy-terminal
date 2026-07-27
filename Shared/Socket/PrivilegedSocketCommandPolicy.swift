// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PrivilegedSocketCommandPolicy.swift - Shared approval policy for local socket commands.

import Foundation

public enum CocxyPrivilegedSocketCommandCategory: String, Equatable, Sendable {
    case terminalInput = "terminal-input"
    case terminalRead = "terminal-read"
    case browserControl = "browser-control"
    case browserRead = "browser-read"
    case providerCredentialUse = "provider-credential-use"
    case terminalSharing = "terminal-sharing"
    case localExecution = "local-execution"
    case computeControl = "compute-control"
    case remoteConnection = "remote-connection"
}

public enum CocxyPrivilegedSocketCommandPolicy {
    public static func category(
        forRawCommand command: String
    ) -> CocxyPrivilegedSocketCommandCategory? {
        switch command {
        case "send",
             "send-key",
             "stream-current",
             "protocol-capabilities",
             "protocol-viewport",
             "protocol-send",
             "core-reset",
             "core-signal",
             "block-rerun",
             "image-delete",
             "image-clear":
            return .terminalInput

        case "capture-pane",
             "timeline-show",
             "timeline-export",
             "search",
             "stream-list",
             "core-process",
             "core-modes",
             "core-search",
             "core-ligatures",
             "core-protocol",
             "core-selection",
             "core-font-metrics",
             "core-preedit",
             "core-semantic",
             "block-list",
             "block-outputs",
             "block-copy",
             "image-list",
             "web-status":
            return .terminalRead

        case "browser-navigate",
             "browser-back",
             "browser-forward",
             "browser-reload",
             "browser-state-load",
             "browser-eval",
             "browser-add-script",
             "browser-add-style",
             "browser-init-script-remove",
             "browser-dialog-accept",
             "browser-dialog-dismiss",
             "browser-click",
             "browser-dblclick",
             "browser-hover",
             "browser-focus",
             "browser-fill",
             "browser-upload",
             "browser-type",
             "browser-press",
             "browser-keydown",
             "browser-keyup",
             "browser-check",
             "browser-uncheck",
             "browser-select",
             "browser-scroll",
             "browser-scroll-into-view",
             "browser-cookies-set",
             "browser-cookies-delete",
             "browser-storage-set",
             "browser-storage-delete",
             "browser-import-run":
            return .browserControl

        case "browser-get-state",
             "browser-state-save",
             "browser-init-scripts-list",
             "browser-dialogs",
             "browser-get-text",
             "browser-list-tabs",
             "browser-snapshot",
             "browser-context",
             "browser-get-html",
             "browser-get-value",
             "browser-get-attr",
             "browser-get-title",
             "browser-get-count",
             "browser-get-box",
             "browser-get-styles",
             "browser-is-visible",
             "browser-is-enabled",
             "browser-is-checked",
             "browser-find-role",
             "browser-find-text",
             "browser-find-label",
             "browser-find-placeholder",
             "browser-find-alt",
             "browser-find-title",
             "browser-find-testid",
             "browser-find-first",
             "browser-find-last",
             "browser-find-nth",
             "browser-screenshot",
             "browser-console",
             "browser-wait",
             "browser-cookies-list",
             "browser-network",
             "browser-frames",
             "browser-downloads",
             "browser-storage-list",
             "browser-storage-get",
             "browser-import-preview":
            return .browserRead

        case "git-assistant-commit-message",
             "git-assistant-pr-draft",
             "git-assistant-release-notes":
            return .providerCredentialUse

        case "web-start", "web-stop":
            return .terminalSharing

        case "notebook-import",
             "notebook-export",
             "notebook-export-html",
             "notebook-template-create",
             "notebook-run",
             "workflow-run",
             "agent-team-launch",
             "agent-team-stop":
            return .localExecution

        case "cell-create",
             "cell-list",
             "cell-exec",
             "cell-attach",
             "cell-destroy",
             "cell-logs",
             "cell-status":
            return .computeControl

        case "ssh":
            return .remoteConnection

        default:
            return nil
        }
    }

    public static func requiresApproval(_ command: String) -> Bool {
        category(forRawCommand: command) != nil
    }
}
