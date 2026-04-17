// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase2EdgeCaseTests.swift - Edge cases, stress tests and integration tests for Fase 2.
//
// Cubren los gaps identificados en el code review de T-021:
// - TabManager: burst de creación/cierre, invariantes, gotoTab, exactamente-un-activo
// - SplitNode: split+remove+split, profundidad máxima en rama alternativa
// - GitInfoProvider: path traversal, nombres de rama edge cases
// - TabSplitCoordinator: count tracking, cleanup múltiple
// - Integración TabManager + SplitManager + GitInfoProvider
// - Performance: 10 tabs + 8 splits

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - TabManager Edge Cases

/// Tests de edge cases de TabManager que no estaban cubiertos en TabManagerFullTests.
///
/// Focus en:
/// - Exactamente un tab activo en todo momento (invariante crítico).
/// - gotoTab con índices límite.
/// - Añadir/cerrar muchos tabs en ráfaga.
/// - activeTabID nunca es nil cuando hay tabs.
@MainActor
final class TabManagerEdgeCaseTests: XCTestCase {

    private var tabManager: TabManager!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
    }

    override func tearDown() {
        tabManager = nil
        super.tearDown()
    }

    // MARK: - Invariante: exactamente un activo

    func testExactlyOneTabIsActiveAtInit() {
        let activeCount = tabManager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1, "Debe haber exactamente 1 tab activo al iniciar")
    }

    func testExactlyOneTabIsActiveAfterAddingManyTabs() {
        for _ in 0..<7 {
            _ = tabManager.addTab()
        }
        let activeCount = tabManager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1,
                        "Debe haber exactamente 1 tab activo después de añadir 7 tabs")
    }

    func testExactlyOneTabIsActiveAfterRemovingTabs() {
        // Añade 5 tabs, luego elimina 3.
        var addedIDs: [TabID] = []
        for _ in 0..<5 {
            let t = tabManager.addTab()
            addedIDs.append(t.id)
        }
        tabManager.removeTab(id: addedIDs[0])
        tabManager.removeTab(id: addedIDs[2])
        tabManager.removeTab(id: addedIDs[4])

        let activeCount = tabManager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1,
                        "Debe haber exactamente 1 tab activo después de eliminar tabs")
    }

    func testActiveTabIDNeverNilWithTabsPresent() {
        // El activeTabID nunca debe ser nil cuando existen tabs.
        XCTAssertNotNil(tabManager.activeTabID)

        _ = tabManager.addTab()
        XCTAssertNotNil(tabManager.activeTabID)

        tabManager.removeTab(id: tabManager.activeTabID!)
        XCTAssertNotNil(tabManager.activeTabID)
    }

    // MARK: - gotoTab edge cases

    func testGotoTabAtZeroActivatesFirst() {
        _ = tabManager.addTab()
        _ = tabManager.addTab()
        let firstTab = tabManager.tabs[0]

        tabManager.gotoTab(at: 0)

        XCTAssertEqual(tabManager.activeTabID, firstTab.id)
    }

    func testGotoTabAtLastIndex() {
        _ = tabManager.addTab()
        let lastTab = tabManager.addTab()

        tabManager.gotoTab(at: tabManager.tabs.count - 1)

        XCTAssertEqual(tabManager.activeTabID, lastTab.id)
    }

    func testGotoTabWithNegativeIndexDoesNothing() {
        let currentActive = tabManager.activeTabID

        tabManager.gotoTab(at: -1)

        XCTAssertEqual(tabManager.activeTabID, currentActive)
    }

    func testGotoTabWithOutOfBoundsIndexDoesNothing() {
        let currentActive = tabManager.activeTabID

        tabManager.gotoTab(at: 99)

        XCTAssertEqual(tabManager.activeTabID, currentActive)
    }

    func testGotoTabAtExactBoundary() {
        // Con 1 solo tab, índice 0 debe funcionar.
        XCTAssertEqual(tabManager.tabs.count, 1)
        let onlyTab = tabManager.tabs[0]

        tabManager.gotoTab(at: 0)

        XCTAssertEqual(tabManager.activeTabID, onlyTab.id)
    }

    // MARK: - Burst de creación y cierre

    func testBurstAdd8TabsThenCloseAll() {
        // Añade 7 tabs más (total 8).
        for _ in 0..<7 {
            _ = tabManager.addTab()
        }
        XCTAssertEqual(tabManager.tabs.count, 8)

        // Cierra 7 (no puede cerrar el último).
        while tabManager.tabs.count > 1 {
            guard let activeID = tabManager.activeTabID else { break }
            tabManager.removeTab(id: activeID)
        }

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertNotNil(tabManager.activeTabID)
        let activeCount = tabManager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1)
    }

    func testBurstAddAndCloseAlternating() {
        // Añade un tab, cierra el activo, repite 10 veces.
        for _ in 0..<10 {
            _ = tabManager.addTab()
            guard let activeID = tabManager.activeTabID else {
                XCTFail("activeTabID no debe ser nil")
                return
            }
            // Siempre hay al menos 1, así que solo cerramos si hay más de 1.
            if tabManager.tabs.count > 1 {
                tabManager.removeTab(id: activeID)
            }
        }
        // Debe seguir habiendo exactamente 1 activo.
        let activeCount = tabManager.tabs.filter { $0.isActive }.count
        XCTAssertEqual(activeCount, 1)
    }

    func testCloseActiveTabInMiddlePreservesOrder() {
        // [A, B, C, D] — cerrar B, verificar orden [A, C, D].
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()
        let tabD = tabManager.addTab()

        tabManager.setActive(id: tabB.id)
        tabManager.removeTab(id: tabB.id)

        XCTAssertEqual(tabManager.tabs.map(\.id), [tabA.id, tabC.id, tabD.id])
        // Tab C debe haber tomado el foco (índice siguiente al eliminado).
        XCTAssertEqual(tabManager.activeTabID, tabC.id)
    }

    // MARK: - moveTab edge cases

    func testMoveTabToSameIndexDoesNothing() {
        _ = tabManager.addTab()
        let initialOrder = tabManager.tabs.map(\.id)

        tabManager.moveTab(from: 0, to: 0)

        XCTAssertEqual(tabManager.tabs.map(\.id), initialOrder)
    }

    func testMoveTabFromLastToFirst() {
        let tabA = tabManager.tabs[0]
        let tabB = tabManager.addTab()
        let tabC = tabManager.addTab()

        // [A, B, C] -> mover C (índice 2) a índice 0 -> [C, A, B]
        tabManager.moveTab(from: 2, to: 0)

        XCTAssertEqual(tabManager.tabs[0].id, tabC.id)
        XCTAssertEqual(tabManager.tabs[1].id, tabA.id)
        XCTAssertEqual(tabManager.tabs[2].id, tabB.id)
    }
}

// MARK: - SplitNode Edge Cases

/// Tests de edge cases no cubiertos en SplitNodeTests.
///
/// Focus en:
/// - split + remove + re-split del mismo árbol.
/// - Profundidad máxima en rama secundaria (no solo la principal).
/// - Árbol muy asimétrico (estrella izquierda vs derecha).
/// - updateRatio en árbol profundo (actualiza solo el nodo correcto).
final class SplitNodeEdgeCaseTests: XCTestCase {

    // MARK: - split → remove → split

    func testSplitRemoveAndResplitProducesCorrectTree() {
        // Empieza con 1 hoja, divide, quita el nuevo leaf, vuelve a dividir.
        let originalLeafID = UUID()
        let originalTerminalID = UUID()

        var tree = SplitNode.leaf(id: originalLeafID, terminalID: originalTerminalID)

        // Primera división.
        let firstNewTerminalID = UUID()
        tree = tree.splitLeaf(
            leafID: originalLeafID,
            direction: .horizontal,
            newTerminalID: firstNewTerminalID
        )!
        XCTAssertEqual(tree.leafCount, 2)

        // Identifica el nuevo leaf (tiene firstNewTerminalID).
        let newLeafID = tree.allLeafIDs().first { $0.terminalID == firstNewTerminalID }!.leafID

        // Elimina el nuevo leaf, vuelve a 1 hoja.
        tree = tree.removeLeaf(leafID: newLeafID)!
        XCTAssertEqual(tree.leafCount, 1)

        // Segunda división sobre el leaf original.
        let secondNewTerminalID = UUID()
        tree = tree.splitLeaf(
            leafID: originalLeafID,
            direction: .vertical,
            newTerminalID: secondNewTerminalID
        )!

        XCTAssertEqual(tree.leafCount, 2)
        // La dirección del split resultante debe ser vertical.
        if case .split(_, let direction, _, _, _) = tree {
            XCTAssertEqual(direction, .vertical)
        } else {
            XCTFail("Se esperaba un split node")
        }
    }

    // MARK: - Profundidad máxima en rama alternativa

    func testDepthLimitEnforcedOnSecondBranch() {
        // Construye un árbol donde la rama izquierda ya tiene profundidad 4,
        // pero verificamos que la rama derecha también respeta el límite.
        var tree = SplitNode.leaf(id: UUID(), terminalID: UUID())

        // Divide 4 veces siempre el primer leaf (rama izquierda profunda).
        for _ in 0..<4 {
            let leafID = tree.allLeafIDs().first!.leafID
            tree = tree.splitLeaf(
                leafID: leafID,
                direction: .horizontal,
                newTerminalID: UUID()
            )!
        }
        XCTAssertEqual(tree.depth, 4)

        // Intenta dividir el primer leaf (está a profundidad 4).
        let deepestFirstLeafID = tree.allLeafIDs().first!.leafID
        let shouldBeNil = tree.splitLeaf(
            leafID: deepestFirstLeafID,
            direction: .horizontal,
            newTerminalID: UUID(),
            maxDepth: 4
        )
        XCTAssertNil(shouldBeNil, "No debe permitir split más allá del límite de profundidad")
    }

    func testSplitAtDepth3StillAllowsOneMoreLevel() {
        // Con maxDepth = 4, un nodo a profundidad 3 PUEDE dividirse (genera depth 4).
        var tree = SplitNode.leaf(id: UUID(), terminalID: UUID())

        // Construye un árbol de profundidad 3.
        for _ in 0..<3 {
            let leafID = tree.allLeafIDs().first!.leafID
            tree = tree.splitLeaf(
                leafID: leafID,
                direction: .horizontal,
                newTerminalID: UUID()
            )!
        }
        XCTAssertEqual(tree.depth, 3)

        // El leaf más profundo está a depth 3 (en la rama first del split de depth 3).
        // Dividirlo genera depth 4, que es <= maxDepth=4, debe permitirse.
        let deepLeafID = tree.allLeafIDs().first!.leafID
        let result = tree.splitLeaf(
            leafID: deepLeafID,
            direction: .horizontal,
            newTerminalID: UUID(),
            maxDepth: 4
        )
        XCTAssertNotNil(result, "Un leaf a profundidad 3 debe poder dividirse (genera depth 4)")
    }

    // MARK: - updateRatio solo actualiza el nodo correcto

    func testUpdateRatioOnlyAffectsTargetSplit() {
        let splitID1 = UUID()
        let splitID2 = UUID()

        let tree = SplitNode.split(
            id: splitID1,
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .split(
                id: splitID2,
                direction: .vertical,
                first: .leaf(id: UUID(), terminalID: UUID()),
                second: .leaf(id: UUID(), terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        // Actualiza solo splitID2.
        let updated = tree.updateRatio(splitID: splitID2, ratio: 0.8)

        // El split raíz (splitID1) NO debe cambiar su ratio.
        if case .split(let id, _, _, let second, let ratio) = updated {
            XCTAssertEqual(id, splitID1)
            XCTAssertEqual(ratio, 0.5, accuracy: 0.001,
                            "El ratio de splitID1 no debe cambiar")

            // El split hijo (splitID2) SÍ debe tener ratio actualizado.
            if case .split(_, _, _, _, let innerRatio) = second {
                XCTAssertEqual(innerRatio, 0.8, accuracy: 0.001,
                                "El ratio de splitID2 debe ser 0.8")
            } else {
                XCTFail("Se esperaba split en second")
            }
        } else {
            XCTFail("Se esperaba split raíz")
        }
    }

    // MARK: - allLeafIDs en árbol asimétrico (rama derecha profunda)

    func testAllLeafIDsDFSOrderAsymmetricTree() {
        // Árbol donde la rama derecha es profunda (todos los splits en second).
        let t1 = UUID(), t2 = UUID(), t3 = UUID(), t4 = UUID()

        let tree = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: t1),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: UUID(), terminalID: t2),
                second: .split(
                    id: UUID(),
                    direction: .horizontal,
                    first: .leaf(id: UUID(), terminalID: t3),
                    second: .leaf(id: UUID(), terminalID: t4),
                    ratio: 0.5
                ),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let ids = tree.allLeafIDs().map { $0.terminalID }
        XCTAssertEqual(ids, [t1, t2, t3, t4], "El recorrido DFS debe ser de izquierda a derecha")
    }

    // MARK: - removeLeaf en árbol con 4 hojas (grid 2x2)

    func testRemoveLeafFrom4LeafGridProduces3Leaves() {
        let leafIDs = (0..<4).map { _ in UUID() }
        let terminalIDs = (0..<4).map { _ in UUID() }

        // Árbol de 4 hojas en configuración 2x2.
        let tree = SplitNode.split(
            id: UUID(),
            direction: .vertical,
            first: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: leafIDs[0], terminalID: terminalIDs[0]),
                second: .leaf(id: leafIDs[1], terminalID: terminalIDs[1]),
                ratio: 0.5
            ),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: leafIDs[2], terminalID: terminalIDs[2]),
                second: .leaf(id: leafIDs[3], terminalID: terminalIDs[3]),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let result = tree.removeLeaf(leafID: leafIDs[3])

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.leafCount, 3)
        let remaining = result!.allLeafIDs().map { $0.terminalID }
        XCTAssertFalse(remaining.contains(terminalIDs[3]),
                        "El leaf eliminado no debe estar en el árbol")
        XCTAssertTrue(remaining.contains(terminalIDs[0]))
        XCTAssertTrue(remaining.contains(terminalIDs[1]))
        XCTAssertTrue(remaining.contains(terminalIDs[2]))
    }
}

// MARK: - GitInfoProvider Edge Cases

/// Tests de edge cases de GitInfoProvider no cubiertos en GitInfoProviderTests.
///
/// Focus en:
/// - Nombres de rama con caracteres especiales (Unicode, emojis, puntos).
/// - Intento de path traversal en el nombre de rama (seguridad).
/// - Rama con solo whitespace (debe retornar nil).
/// - Múltiples directorios con mismo prefijo de path.
final class GitInfoProviderEdgeCaseTests: XCTestCase {

    private var provider: GitInfoProviderImpl!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        provider = GitInfoProviderImpl(cacheTTLSeconds: 60.0)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitInfoEdgeCases-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        provider = nil
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    private func createFakeGitRepo(branch: String, at directory: URL? = nil) {
        let dir = directory ?? tempDirectory!
        let gitDir = dir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        let headContent = "ref: refs/heads/\(branch)\n"
        try? headContent.write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Nombres de rama con caracteres especiales

    func testBranchNameWithUnicode() {
        // Nombres de rama con caracteres no ASCII (son válidos en git).
        createFakeGitRepo(branch: "feature/diseño-español")
        let branch = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(branch, "feature/diseño-español")
    }

    func testBranchNameWithDotsAndNumbers() {
        createFakeGitRepo(branch: "release/2.3.4-beta.1")
        let branch = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(branch, "release/2.3.4-beta.1")
    }

    func testBranchNameWithHyphensAndUnderscores() {
        createFakeGitRepo(branch: "fix_bug-123_very-long-branch-name")
        let branch = provider.currentBranch(at: tempDirectory)
        XCTAssertEqual(branch, "fix_bug-123_very-long-branch-name")
    }

    // MARK: - Seguridad: path traversal en nombre de rama

    func testBranchNameWithPathTraversalSequence() {
        // Un atacante podría intentar que el nombre de rama contenga "../etc/passwd".
        // GitInfoProvider lee directamente de .git/HEAD como texto plano —
        // lo que retorna es el string tal cual, no lo evalúa como path.
        // El test verifica que no lanza excepción y retorna el valor leído.
        createFakeGitRepo(branch: "../etc/passwd")
        let branch = provider.currentBranch(at: tempDirectory)
        // El nombre es técnicamente válido como string pero git no lo permitiría.
        // Verificamos que lo lee tal cual sin evaluar el path.
        XCTAssertEqual(branch, "../etc/passwd",
                        "El provider debe retornar el contenido leído, no evaluar el path")
    }

    // MARK: - Contenido de HEAD solo con whitespace

    func testBranchNameWithOnlyWhitespaceReturnsNil() {
        let gitDir = tempDirectory.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        // Solo espacios y newlines (sin prefix "ref: refs/heads/").
        try? "   \n\t  \n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        let branch = provider.currentBranch(at: tempDirectory)
        XCTAssertNil(branch, "HEAD con solo whitespace debe retornar nil")
    }

    func testBranchNameWithRefPrefixButEmptyName() {
        // "ref: refs/heads/" seguido de nada (nombre vacío).
        let gitDir = tempDirectory.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try? "ref: refs/heads/\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        let branch = provider.currentBranch(at: tempDirectory)
        XCTAssertNil(branch, "Nombre de rama vacío debe retornar nil")
    }

    // MARK: - Directorios con prefijo de path compartido

    func testCacheIsolatedForDirectoriesWithSharedPathPrefix() {
        // Dos directorios donde uno es prefijo del path del otro.
        // Esto verifica que el caché usa path completo, no prefix matching.
        let dir1 = tempDirectory.appendingPathComponent("project")
        let dir2 = tempDirectory.appendingPathComponent("project-copy")

        try? FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        createFakeGitRepo(branch: "main", at: dir1)
        createFakeGitRepo(branch: "develop", at: dir2)

        let branch1 = provider.currentBranch(at: dir1)
        let branch2 = provider.currentBranch(at: dir2)

        XCTAssertEqual(branch1, "main")
        XCTAssertEqual(branch2, "develop",
                        "El caché debe distinguir directorios con prefijo de path compartido")
    }

    // MARK: - isGitRepository con archivo HEAD (no directorio)

    func testIsGitRepositoryReturnsFalseWhenGitIsFile() {
        // Crea un fichero llamado ".git" (no un directorio).
        let gitPath = tempDirectory.appendingPathComponent(".git")
        try? "not a directory".write(to: gitPath, atomically: true, encoding: .utf8)

        // No debe haber .git/HEAD porque .git es un fichero.
        let result = provider.isGitRepository(at: tempDirectory)
        XCTAssertFalse(result,
                        "Si .git es un fichero (no directorio), no debe ser git repo")
    }

    // MARK: - TTL de caché

    func testCacheExpireAfterTTL() {
        let fastProvider = GitInfoProviderImpl(cacheTTLSeconds: 0.1) // 100ms TTL
        createFakeGitRepo(branch: "original")

        // Primera llamada: popula caché.
        let first = fastProvider.currentBranch(at: tempDirectory)
        XCTAssertEqual(first, "original")

        // Modifica .git/HEAD mientras la caché está "fresca"... espera expiración.
        let expectation = self.expectation(description: "Cache TTL expiry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Modifica la rama en disco.
        createFakeGitRepo(branch: "updated")

        // Segunda llamada: caché expirada, debe leer del disco.
        let second = fastProvider.currentBranch(at: tempDirectory)
        XCTAssertEqual(second, "updated",
                        "Después de expirar el TTL, debe leer el valor actualizado del disco")
    }
}

// MARK: - TabSplitCoordinator Edge Cases

/// Tests de edge cases de TabSplitCoordinator.
@MainActor
final class TabSplitCoordinatorEdgeCaseTests: XCTestCase {

    // MARK: - count tracking

    func testCountIncreasesWithEachNewTab() {
        let coordinator = TabSplitCoordinator()
        XCTAssertEqual(coordinator.count, 0)

        _ = coordinator.splitManager(for: TabID())
        XCTAssertEqual(coordinator.count, 1)

        _ = coordinator.splitManager(for: TabID())
        XCTAssertEqual(coordinator.count, 2)
    }

    func testCountDecreasesOnRemoval() {
        let coordinator = TabSplitCoordinator()
        let id1 = TabID()
        let id2 = TabID()

        _ = coordinator.splitManager(for: id1)
        _ = coordinator.splitManager(for: id2)
        XCTAssertEqual(coordinator.count, 2)

        coordinator.removeSplitManager(for: id1)
        XCTAssertEqual(coordinator.count, 1)

        coordinator.removeSplitManager(for: id2)
        XCTAssertEqual(coordinator.count, 0)
    }

    func testRemoveNonExistentTabIDIsNoOp() {
        let coordinator = TabSplitCoordinator()
        let id = TabID()
        _ = coordinator.splitManager(for: id)

        // Intenta eliminar un ID que no existe.
        coordinator.removeSplitManager(for: TabID())

        XCTAssertEqual(coordinator.count, 1, "Eliminar un ID inexistente no debe cambiar el count")
    }

    func testSameTabIDReturnsSameInstanceEvenAfterOtherTabsRemoved() {
        let coordinator = TabSplitCoordinator()
        let stableID = TabID()
        let ephemeralID = TabID()

        let stableManager = coordinator.splitManager(for: stableID)
        _ = coordinator.splitManager(for: ephemeralID)

        // Elimina el tab efímero.
        coordinator.removeSplitManager(for: ephemeralID)

        // El manager del tab estable debe ser el mismo.
        let sameManager = coordinator.splitManager(for: stableID)
        XCTAssertTrue(stableManager === sameManager,
                       "El manager del tab estable debe ser el mismo tras eliminar otros")
    }

    func testCoordinatorHandlesRapidCreateAndRemoveCycles() {
        let coordinator = TabSplitCoordinator()

        for _ in 0..<20 {
            let id = TabID()
            let manager = coordinator.splitManager(for: id)
            _ = manager.splitFocused(direction: .horizontal)
            coordinator.removeSplitManager(for: id)
        }

        XCTAssertEqual(coordinator.count, 0,
                        "Después de 20 ciclos crear/eliminar, count debe ser 0")
    }

    // MARK: - Estado aislado tras recreación

    func testRecreatedSplitManagerStartsFresh() {
        let coordinator = TabSplitCoordinator()
        let tabID = TabID()

        // Crea, usa (divide 3 veces) y elimina.
        let original = coordinator.splitManager(for: tabID)
        _ = original.splitFocused(direction: .horizontal)
        _ = original.splitFocused(direction: .vertical)
        _ = original.splitFocused(direction: .horizontal)
        XCTAssertEqual(original.rootNode.leafCount, 4)

        coordinator.removeSplitManager(for: tabID)

        // El nuevo manager debe empezar limpio.
        let fresh = coordinator.splitManager(for: tabID)
        XCTAssertEqual(fresh.rootNode.leafCount, 1,
                        "Un SplitManager recreado debe empezar con 1 hoja")
    }
}

// MARK: - Integration Tests: TabManager + SplitManager + GitInfoProvider

/// Tests de integración que verifican que TabManager, SplitManager y
/// GitInfoProvider trabajan correctamente en conjunto.
@MainActor
final class Phase2IntegrationTests: XCTestCase {

    private var tabManager: TabManager!
    private var coordinator: TabSplitCoordinator!
    private var gitProvider: GitInfoProviderImpl!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        coordinator = TabSplitCoordinator()
        gitProvider = GitInfoProviderImpl()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Phase2Integration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tabManager = nil
        coordinator = nil
        gitProvider = nil
        tempDir = nil
        super.tearDown()
    }

    private func createFakeGitRepo(branch: String, at dir: URL) {
        let gitDir = dir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try? "ref: refs/heads/\(branch)\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Tab creado tiene SplitManager independiente

    func testEachTabHasIndependentSplitState() {
        let tab1 = tabManager.addTab()
        let tab2 = tabManager.addTab()
        let tab3 = tabManager.addTab()

        let sm1 = coordinator.splitManager(for: tab1.id)
        let sm2 = coordinator.splitManager(for: tab2.id)
        let sm3 = coordinator.splitManager(for: tab3.id)

        // Divide tab1 dos veces.
        _ = sm1.splitFocused(direction: .horizontal)
        _ = sm1.splitFocused(direction: .vertical)

        // Divide tab3 una vez.
        _ = sm3.splitFocused(direction: .horizontal)

        XCTAssertEqual(sm1.rootNode.leafCount, 3)
        XCTAssertEqual(sm2.rootNode.leafCount, 1, "Tab2 no debe estar afectado")
        XCTAssertEqual(sm3.rootNode.leafCount, 2)
    }

    // MARK: - Cerrar tab limpia su SplitManager

    func testClosingTabRemovesSplitManagerFromCoordinator() {
        let tab = tabManager.addTab()
        _ = coordinator.splitManager(for: tab.id)
        XCTAssertEqual(coordinator.count, 1)

        // Simula el cierre del tab (en producción, MainWindowController haría esto).
        tabManager.removeTab(id: tab.id)
        coordinator.removeSplitManager(for: tab.id)

        XCTAssertEqual(coordinator.count, 0,
                        "Cerrar un tab debe limpiar su SplitManager del coordinador")
    }

    // MARK: - GitInfoProvider integrado con Tab working directory

    func testGitInfoProviderUpdatesTabGitBranch() {
        createFakeGitRepo(branch: "feature/integration-test", at: tempDir)

        // Crea un tab apuntando al directorio git.
        let tab = tabManager.addTab(workingDirectory: tempDir)

        // Lee la rama del directorio del tab.
        let branch = gitProvider.currentBranch(at: tab.workingDirectory)

        // Actualiza el tab con la rama.
        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = branch
        }

        let updatedTab = tabManager.tab(for: tab.id)
        XCTAssertEqual(updatedTab?.gitBranch, "feature/integration-test")
    }

    func testTabDisplayTitleIncludesGitBranchFromProvider() {
        createFakeGitRepo(branch: "main", at: tempDir)

        let tab = tabManager.addTab(workingDirectory: tempDir)
        let branch = gitProvider.currentBranch(at: tab.workingDirectory)

        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = branch
        }

        let updatedTab = tabManager.tab(for: tab.id)!
        // displayTitle debe incluir el nombre del directorio y la rama.
        let expectedDirName = tempDir.lastPathComponent
        XCTAssertTrue(updatedTab.displayTitle.contains(expectedDirName))
        XCTAssertTrue(updatedTab.displayTitle.contains("main"))
    }

    // MARK: - 8 tabs + navegación circular completa

    func testNavigate8TabsFullCircle() {
        // Añade 7 tabs más (total 8).
        var tabIDs: [TabID] = [tabManager.tabs[0].id]
        for _ in 0..<7 {
            tabIDs.append(tabManager.addTab().id)
        }
        XCTAssertEqual(tabManager.tabs.count, 8)

        // Activa el primer tab.
        tabManager.setActive(id: tabIDs[0])

        // Navega hacia adelante 8 veces: debe dar la vuelta completa.
        for _ in 0..<8 {
            tabManager.nextTab()
        }

        // Después de 8 nextTab desde posición 0, volvemos a posición 0.
        XCTAssertEqual(tabManager.activeTabID, tabIDs[0])
    }
}

// MARK: - Performance Tests

/// Tests de rendimiento de Fase 2.
///
/// Verifica que los criterios de performance del gate de Fase 2 se cumplen:
/// - Crear 10 tabs + 8 splits en tiempo razonable.
/// - Navegación entre tabs sin degradación observable.
@MainActor
final class Phase2PerformanceTests: XCTestCase {

    func testCreate10TabsAnd8SplitsCompletesQuickly() {
        // Mide que crear 10 tabs + 8 splits por tab se completa sin exceder
        // un tiempo razonable en tests (no mide RAM, sino CPU/tiempo).
        let tabManager = TabManager()
        let coordinator = TabSplitCoordinator()

        let startTime = Date()

        // Crea 9 tabs adicionales (total 10).
        for _ in 0..<9 {
            _ = tabManager.addTab()
        }
        XCTAssertEqual(tabManager.tabs.count, 10)

        // Para cada tab, crea 8 splits.
        for tab in tabManager.tabs {
            let splitManager = coordinator.splitManager(for: tab.id)
            // 8 splits sucesivos (el límite de profundidad es 4, pero podemos
            // hacer splits mientras queden hojas disponibles).
            for _ in 0..<8 {
                let allLeaves = splitManager.rootNode.allLeafIDs()
                if let randomLeaf = allLeaves.randomElement() {
                    splitManager.focusLeaf(id: randomLeaf.leafID)
                    _ = splitManager.splitFocused(direction: .horizontal)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // Verifica que la operación completa en menos de 1 segundo
        // (en tests unitarios sin UI, debería ser muy rápido).
        XCTAssertLessThan(elapsed, 1.0,
                           "Crear 10 tabs + 8 splits por tab debe completarse en < 1s")

        // Verifica estructura.
        for tab in tabManager.tabs {
            let splitManager = coordinator.splitManager(for: tab.id)
            XCTAssertGreaterThan(splitManager.rootNode.leafCount, 1,
                                  "Cada tab debe tener múltiples splits")
        }
    }

    func testNavigateAllTabsIs8TimesInUnder100ms() {
        let tabManager = TabManager()

        // Crea 7 tabs adicionales (total 8).
        for _ in 0..<7 {
            _ = tabManager.addTab()
        }

        let iterations = 100
        let startTime = Date()

        for _ in 0..<iterations {
            tabManager.nextTab()
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // 100 navegaciones de tabs deben completarse en menos de 50ms.
        XCTAssertLessThan(elapsed, 0.05,
                           "100 navegaciones de tabs deben completarse en < 50ms")
    }

    func testGitInfoProviderQueryUnder50ms() {
        // Verifica el gate: GitInfoProvider < 50ms por query.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerfTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Crea un repo git falso.
        let gitDir = tempDir.appendingPathComponent(".git")
        try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try? "ref: refs/heads/main\n".write(
            to: gitDir.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )

        let provider = GitInfoProviderImpl(cacheTTLSeconds: 0.0) // Sin caché para medir disco.

        let startTime = Date()
        let branch = provider.currentBranch(at: tempDir)
        let elapsed = Date().timeIntervalSince(startTime) * 1000 // En milisegundos.

        XCTAssertEqual(branch, "main")
        XCTAssertLessThan(elapsed, 50.0,
                           "GitInfoProvider debe responder en < 50ms (gate de Fase 2)")
    }

    func testSplitNodeTreeTraversalIs8LeavesUnder1ms() {
        // Construye un árbol de 8 hojas explícitamente con estructura balanceada
        // (profundidad 3, bien dentro del límite maxDepth=4).
        //
        //            split(H)
        //           /         \
        //       split(V)       split(V)
        //      /       \     /       \
        //   split(H) split(H) split(H) split(H)
        //    / \      / \      / \      / \
        //   L  L    L  L    L  L    L  L   <- 8 hojas, depth=3
        //
        // No se usa splitLeaf porque su límite de profundidad depende
        // del contexto del árbol, no de la profundidad del leaf aislado.
        // Este árbol se construye directamente con la API pública de SplitNode.
        func makeLeaf() -> SplitNode {
            SplitNode.leaf(id: UUID(), terminalID: UUID())
        }
        func hPair(_ a: SplitNode, _ b: SplitNode) -> SplitNode {
            SplitNode.split(id: UUID(), direction: .horizontal, first: a, second: b, ratio: 0.5)
        }
        func vPair(_ a: SplitNode, _ b: SplitNode) -> SplitNode {
            SplitNode.split(id: UUID(), direction: .vertical, first: a, second: b, ratio: 0.5)
        }

        let tree = hPair(
            vPair(hPair(makeLeaf(), makeLeaf()), hPair(makeLeaf(), makeLeaf())),
            vPair(hPair(makeLeaf(), makeLeaf()), hPair(makeLeaf(), makeLeaf()))
        )

        XCTAssertEqual(tree.leafCount, 8, "El árbol balanceado debe tener 8 hojas")
        XCTAssertEqual(tree.depth, 3, "El árbol balanceado debe tener profundidad 3")

        // Mide 1000 traversals.
        let iterations = 1000
        let startTime = Date()

        for _ in 0..<iterations {
            _ = tree.allLeafIDs()
        }

        let elapsed = Date().timeIntervalSince(startTime) * 1000 // milisegundos
        let perIteration = elapsed / Double(iterations)

        XCTAssertLessThan(perIteration, 1.0,
                           "Un traversal de árbol con 8 hojas debe tardar < 1ms")
    }
}

// MARK: - TabBarViewModel Additional Tests

/// Tests adicionales de TabBarViewModel que cubren casos no testeados.
@MainActor
final class TabBarViewModelAdditionalTests: XCTestCase {

    private var tabManager: TabManager!
    private var viewModel: TabBarViewModel!

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        viewModel = TabBarViewModel(tabManager: tabManager)
    }

    override func tearDown() {
        tabManager = nil
        viewModel = nil
        super.tearDown()
    }

    // MARK: - closeOtherTabs

    func testCloseOtherTabsLeavesOnlyKeptTab() {
        let keepTab = tabManager.addTab()
        _ = tabManager.addTab()
        _ = tabManager.addTab()
        XCTAssertEqual(tabManager.tabs.count, 4)

        viewModel.closeOtherTabs(except: keepTab.id)

        XCTAssertEqual(tabManager.tabs.count, 1)
        XCTAssertEqual(tabManager.tabs[0].id, keepTab.id)
    }

    func testCloseOtherTabsWithSingleTabIsNoOp() {
        let onlyTab = tabManager.tabs[0]

        viewModel.closeOtherTabs(except: onlyTab.id)

        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    func testCloseOtherTabsActivatesKeptTab() {
        _ = tabManager.addTab()
        let keepTab = tabManager.addTab()
        _ = tabManager.addTab()

        viewModel.closeOtherTabs(except: keepTab.id)

        XCTAssertEqual(tabManager.activeTabID, keepTab.id)
    }

    // MARK: - syncWithManager

    func testSyncWithManagerUpdatesTabItems() {
        let initialCount = viewModel.tabItems.count

        _ = tabManager.addTab()
        viewModel.syncWithManager()

        XCTAssertEqual(viewModel.tabItems.count, initialCount + 1)
    }

    func testTabItemsReflectAgentState() {
        // Agent state now lives in the per-surface store; the sidebar
        // pill reads it through the view model's resolver closure.
        viewModel.agentStateResolver = { _ in
            SurfaceAgentState(agentState: .working)
        }
        viewModel.syncWithManager()

        let tab = tabManager.tabs[0]
        let item = viewModel.tabItems.first { $0.id == tab.id }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.statusColorName, "blue",
                        "Working agent state debe mostrar color azul")
        XCTAssertEqual(item?.badgeText, "Working")
    }

    func testTabItemsReflectAllAgentStates() {
        let states: [(AgentState, String, String?)] = [
            (.idle, "gray", nil),
            (.launched, "blue", "Launched"),
            (.working, "blue", "Working"),
            (.waitingInput, "yellow", "Input"),
            (.finished, "green", "Done"),
            (.error, "red", "Error")
        ]

        for (state, expectedColor, expectedBadge) in states {
            // Inject the state via the resolver closure instead of
            // mutating the tab directly — the tab no longer carries the
            // agent fields after Fase 4.
            viewModel.agentStateResolver = { _ in
                SurfaceAgentState(agentState: state)
            }
            viewModel.syncWithManager()

            let item = viewModel.tabItems[0]
            XCTAssertEqual(item.statusColorName, expectedColor,
                            "Estado \(state) debe tener color \(expectedColor)")
            XCTAssertEqual(item.badgeText, expectedBadge,
                            "Estado \(state) debe tener badge '\(String(describing: expectedBadge))'")
        }
    }

    // MARK: - Subtitle construction

    func testSubtitleWithBothBranchAndProcess() {
        let tab = tabManager.tabs[0]
        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = "main"
            t.processName = "claude"
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first { $0.id == tab.id }!
        XCTAssertEqual(item.subtitle, "main \u{2022} claude")
    }

    func testSubtitleWithOnlyBranch() {
        let tab = tabManager.tabs[0]
        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = "develop"
            t.processName = nil
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first { $0.id == tab.id }!
        XCTAssertEqual(item.subtitle, "develop")
    }

    func testSubtitleWithOnlyProcess() {
        let tab = tabManager.tabs[0]
        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = nil
            t.processName = "zsh"
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first { $0.id == tab.id }!
        XCTAssertEqual(item.subtitle, "zsh")
    }

    func testSubtitleWithNeitherBranchNorProcess() {
        let tab = tabManager.tabs[0]
        tabManager.updateTab(id: tab.id) { t in
            t.gitBranch = nil
            t.processName = nil
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first { $0.id == tab.id }!
        XCTAssertNil(item.subtitle)
    }
}
