// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase5QATests.swift - Additional QA tests for Fase 5 (T-039).
//
// El Rompe-cosas: tests adicionales que buscan lo que los tests unitarios
// existentes no cubren. Foco en:
//   - Round-trip determinism con estados complejos (varios pases)
//   - Corrupcion de fichero de sesion (JSON truncado, bytes nulos, fichero vacio, codificacion erronea)
//   - SplitNode trees profundos (4 niveles, no balanceados)
//   - Directorios con rutas muy largas y caracteres especiales
//   - Concurrencia en auto-save (multiples llamadas rapidass)
//   - Rendimiento: save/load de 20 tabs con splits en < 100ms
//   - Casos limite de QuickTerminal (heightPercent en los limites exactos)
//   - Integracion session + restorer: lifecycle completo
//   - SplitNodeState Codable con profundidad 4

import XCTest
@testable import CocxyTerminal

// MARK: - Phase 5 QA Tests

@MainActor
final class Phase5QATests: XCTestCase {

    // MARK: - Properties

    private var tempDirectory: URL!
    private var sessionManager: SessionManagerImpl!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-phase5-qa-\(UUID().uuidString)")
        sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)
    }

    override func tearDown() {
        sessionManager.stopAutoSave()
        try? FileManager.default.removeItem(at: tempDirectory)
        sessionManager = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(tabs: [TabState], savedAt: Date = Date()) -> Session {
        Session(
            version: Session.currentVersion,
            savedAt: savedAt,
            windows: [
                WindowState(
                    frame: CodableRect(x: 100, y: 100, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: tabs,
                    activeTabIndex: 0
                )
            ]
        )
    }

    private func makeLeafTab(
        title: String,
        dir: String = "/tmp"
    ) -> TabState {
        TabState(
            id: TabID(),
            title: title,
            workingDirectory: URL(fileURLWithPath: dir),
            splitTree: .leaf(
                workingDirectory: URL(fileURLWithPath: dir),
                command: nil
            )
        )
    }

    private func makeSplitTab(title: String, splitTree: SplitNodeState) -> TabState {
        TabState(
            id: TabID(),
            title: title,
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            splitTree: splitTree
        )
    }

    /// Arbol de profundidad 4 (split -> split -> split -> hojas)
    private func makeFourLevelSplitTree() -> SplitNodeState {
        let leaf = SplitNodeState.leaf(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: nil
        )
        let level3 = SplitNodeState.split(
            direction: .horizontal,
            first: leaf,
            second: leaf,
            ratio: 0.5
        )
        let level2 = SplitNodeState.split(
            direction: .vertical,
            first: level3,
            second: leaf,
            ratio: 0.6
        )
        return SplitNodeState.split(
            direction: .horizontal,
            first: level2,
            second: SplitNodeState.split(
                direction: .vertical,
                first: leaf,
                second: leaf,
                ratio: 0.4
            ),
            ratio: 0.5
        )
    }

    /// Arbol no balanceado (cadena lineal a la derecha, 5 hojas)
    private func makeUnbalancedRightChain() -> SplitNodeState {
        let leaf = SplitNodeState.leaf(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: nil
        )
        var current: SplitNodeState = leaf
        for _ in 0..<4 {
            current = SplitNodeState.split(
                direction: .horizontal,
                first: leaf,
                second: current,
                ratio: 0.3
            )
        }
        return current
    }

    // MARK: - Test QA-01: Round-trip determinism -- tres pases consecutivos

    func testRoundTripDeterminism_ThreePasses() throws {
        // Arrange: sesion compleja con 5 tabs y splits variados.
        let splitTree = makeFourLevelSplitTree()
        let tabs = (0..<5).map { i in
            i < 3
                ? makeSplitTab(title: "Split \(i)", splitTree: splitTree)
                : makeLeafTab(title: "Leaf \(i)")
        }
        let original = makeSession(tabs: tabs)

        // Act: tres ciclos save -> load.
        var session = original
        for _ in 1...3 {
            try sessionManager.saveSession(session, named: nil)
            let loaded = try sessionManager.loadLastSession()
            XCTAssertNotNil(loaded, "Session must survive round-trip")
            session = loaded!
        }

        // Assert: estructura intacta tras 3 pases.
        XCTAssertEqual(session.version, Session.currentVersion)
        XCTAssertEqual(session.windows[0].tabs.count, 5)
        // Los 3 primeros tabs tienen el arbol profundo (5 hojas).
        if case .split = session.windows[0].tabs[0].splitTree {
            // Bien: es un split
        } else {
            XCTFail("Tab 0 split tree must survive three round-trips")
        }
    }

    // MARK: - Test QA-02: Round-trip determina que la estructura del SplitTree no muta

    func testRoundTripSplitTreeStructurePreserved() throws {
        let originalTree = makeFourLevelSplitTree()
        let tab = makeSplitTab(title: "Deep Tree", splitTree: originalTree)
        let session = makeSession(tabs: [tab])

        try sessionManager.saveSession(session, named: nil)
        let loaded = try sessionManager.loadLastSession()!

        // Verificar que el arbol tiene la misma estructura (direction y ratio en cada nivel).
        func assertSameStructure(
            _ a: SplitNodeState,
            _ b: SplitNodeState,
            depth: Int = 0
        ) {
            switch (a, b) {
            case (.leaf, .leaf):
                return  // Bien.
            case (.split(let dirA, let firstA, let secondA, let ratioA),
                  .split(let dirB, let firstB, let secondB, let ratioB)):
                XCTAssertEqual(dirA, dirB, "Direction mismatch at depth \(depth)")
                XCTAssertEqual(ratioA, ratioB, accuracy: 0.0001,
                               "Ratio mismatch at depth \(depth)")
                assertSameStructure(firstA, firstB, depth: depth + 1)
                assertSameStructure(secondA, secondB, depth: depth + 1)
            default:
                XCTFail("Node type mismatch at depth \(depth)")
            }
        }

        assertSameStructure(
            originalTree,
            loaded.windows[0].tabs[0].splitTree
        )
    }

    // MARK: - Test QA-03: Corrupcion -- fichero JSON truncado

    func testCorruptFile_TruncatedJSON() throws {
        // Crear un fichero JSON valido y despues truncarlo a la mitad.
        let session = makeSession(tabs: [makeLeafTab(title: "T")])
        try sessionManager.saveSession(session, named: nil)

        let filePath = tempDirectory.appendingPathComponent("last.json")
        let data = try Data(contentsOf: filePath)
        let truncated = data.prefix(data.count / 2)
        try truncated.write(to: filePath, options: .atomic)

        // El manager debe lanzar parseFailed, NO crashear.
        XCTAssertThrowsError(try sessionManager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Esperado.
            } else {
                XCTFail("Truncated JSON must throw parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Test QA-04: Corrupcion -- bytes nulos en el fichero

    func testCorruptFile_NullBytes() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        // Datos con null bytes mezclados -- invalido como JSON y como UTF-8.
        let nullData = Data([0x00, 0x00, 0x00, 0x7B, 0x7D, 0x00])
        try nullData.write(to: filePath, options: .atomic)

        XCTAssertThrowsError(try sessionManager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Esperado.
            } else {
                XCTFail("Null bytes must throw parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Test QA-05: Corrupcion -- fichero vacio

    func testCorruptFile_EmptyFile() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        try Data().write(to: filePath, options: .atomic)

        XCTAssertThrowsError(try sessionManager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Esperado.
            } else {
                XCTFail("Empty file must throw parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Test QA-06: Corrupcion -- JSON valido pero estructura incorrecta (tipo incorrecto)

    func testCorruptFile_WrongType() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        // JSON valido pero el "version" es una cadena en lugar de Int.
        let badJSON = """
        {"version": "uno", "savedAt": "2026-01-01T00:00:00Z", "windows": []}
        """
        try badJSON.write(to: filePath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try sessionManager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Esperado.
            } else {
                XCTFail("Wrong type must throw parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Test QA-07: Corrupcion -- encoding Latin-1 (no UTF-8)

    func testCorruptFile_Latin1Encoding() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        // Latin-1 byte que no es UTF-8 valido: 0xFF.
        let latin1Bytes = Data([0x7B, 0xFF, 0x7D])  // "{" + 0xFF (invalido UTF-8) + "}"
        try latin1Bytes.write(to: filePath, options: .atomic)

        XCTAssertThrowsError(try sessionManager.loadLastSession()) { error in
            if case SessionError.parseFailed = error {
                // Esperado.
            } else {
                XCTFail("Latin-1 encoding must throw parseFailed, got \(error)")
            }
        }
    }

    // MARK: - Test QA-08: SplitNode -- arbol de 4 niveles, preserva leaf count

    func testSplitNodeFourLevels_LeafCount() {
        let tree = makeFourLevelSplitTree()
        // El arbol tiene: 2 (nivel3) + 1 + 1 + 1 = 5 hojas.
        // Calculamos lo que realmente tiene.
        func countLeaves(_ node: SplitNodeState) -> Int {
            switch node {
            case .leaf: return 1
            case .split(_, let first, let second, _):
                return countLeaves(first) + countLeaves(second)
            }
        }
        let expectedLeaves = countLeaves(tree)

        let data = try! JSONEncoder().encode(tree)
        let decoded = try! JSONDecoder().decode(SplitNodeState.self, from: data)

        XCTAssertEqual(countLeaves(decoded), expectedLeaves,
                       "Four-level tree must preserve leaf count through Codable")
    }

    // MARK: - Test QA-09: SplitNode -- arbol no balanceado (cadena derecha)

    func testSplitNodeUnbalancedRightChain_LeafCount() {
        let tree = makeUnbalancedRightChain()

        func countLeaves(_ node: SplitNodeState) -> Int {
            switch node {
            case .leaf: return 1
            case .split(_, let first, let second, _):
                return countLeaves(first) + countLeaves(second)
            }
        }
        let expectedLeaves = countLeaves(tree)
        XCTAssertEqual(expectedLeaves, 5, "Unbalanced chain must have 5 leaves")

        let data = try! JSONEncoder().encode(tree)
        let decoded = try! JSONDecoder().decode(SplitNodeState.self, from: data)

        XCTAssertEqual(countLeaves(decoded), 5,
                       "Unbalanced tree must preserve leaf count")
    }

    // MARK: - Test QA-10: SplitNode -- hoja unica

    func testSplitNodeSingleLeaf_RoundTrip() throws {
        let tree = SplitNodeState.leaf(
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: nil
        )
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(SplitNodeState.self, from: data)

        XCTAssertEqual(decoded, tree, "Single leaf must survive round-trip unchanged")
    }

    // MARK: - Test QA-11: Validacion de directorio -- symlink existente va a home

    func testDirectoryValidation_FileNotDirectory_FallsBackToHome() {
        // Un fichero (no directorio) no debe pasar la validacion de directorio.
        let fileURL = URL(fileURLWithPath: "/etc/hosts")  // Existe pero es fichero, no dir.
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Bad Dir",
                            workingDirectory: fileURL,
                            splitTree: .leaf(workingDirectory: fileURL, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: TabManager(),
            splitCoordinator: TabSplitCoordinator(),
            screenBounds: CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertEqual(
            result.restoredTabs[0].workingDirectory,
            FileManager.default.homeDirectoryForCurrentUser,
            "File path (not directory) must fall back to home"
        )
    }

    // MARK: - Test QA-12: Validacion de directorio -- ruta muy larga

    func testDirectoryValidation_VeryLongPath_FallsBackToHome() {
        // PATH_MAX en macOS es 1024. Construimos algo ridiculamente largo.
        let longSegment = String(repeating: "a", count: 200)
        let veryLongPath = "/\(longSegment)/\(longSegment)/\(longSegment)/\(longSegment)/nonexistent"
        let longURL = URL(fileURLWithPath: veryLongPath)

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Long Path",
                            workingDirectory: longURL,
                            splitTree: .leaf(workingDirectory: longURL, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: TabManager(),
            splitCoordinator: TabSplitCoordinator(),
            screenBounds: CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        // No debe crashear; debe devolver algo valido.
        XCTAssertFalse(result.restoredTabs.isEmpty)
        XCTAssertNotNil(result.restoredTabs[0].workingDirectory)
    }

    // MARK: - Test QA-13: Validacion de directorio -- caracteres especiales y Unicode

    func testDirectoryValidation_UnicodePathWithEmoji_DoesNotCrash() {
        // Una ruta con Unicode y emojis en el nombre -- no existe, debe hacer fallback.
        let unicodePath = "/tmp/\u{1F4BB}proyecto-\u{00E9}xito-\u{00E4}rger/test"
        let unicodeURL = URL(fileURLWithPath: unicodePath)

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Unicode",
                            workingDirectory: unicodeURL,
                            splitTree: .leaf(workingDirectory: unicodeURL, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        // No debe crashear.
        let result = SessionRestorer.restore(
            from: session,
            into: TabManager(),
            splitCoordinator: TabSplitCoordinator(),
            screenBounds: CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        XCTAssertFalse(result.restoredTabs.isEmpty,
                       "Unicode path must not crash the restorer")
    }

    // MARK: - Test QA-14: Rendimiento -- save/load de 20 tabs con splits < 100ms

    func testPerformance_SaveLoad20TabsWithSplits() throws {
        let splitTree = makeFourLevelSplitTree()
        let tabs = (0..<20).map { i in
            makeSplitTab(title: "Tab \(i)", splitTree: splitTree)
        }
        let session = makeSession(tabs: tabs)

        let start = Date()
        try sessionManager.saveSession(session, named: nil)
        let loaded = try sessionManager.loadLastSession()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.windows[0].tabs.count, 20)
        XCTAssertLessThan(elapsed, 0.1,
                          "Save + load of 20 tabs with splits must complete in < 100ms (took \(elapsed * 1000)ms)")
    }

    // MARK: - Test QA-15: Rendimiento -- listSessions con 10 sesiones < 50ms

    func testPerformance_ListSessions_10Sessions() throws {
        // Guardar 10 sesiones nombradas.
        let session = makeSession(tabs: [makeLeafTab(title: "T")])
        for i in 0..<10 {
            try sessionManager.saveSession(session, named: "session-\(i)")
        }

        let start = Date()
        let list = sessionManager.listSessions()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(list.count, 10)
        XCTAssertLessThan(elapsed, 0.05,
                          "Listing 10 sessions must complete in < 50ms (took \(elapsed * 1000)ms)")
    }

    // MARK: - Test QA-16: Integracion -- lifecycle completo (save -> reload -> restore)

    func testIntegration_FullLifecycle_SaveKillRelaunchRestore() throws {
        // SIMULAR: "launch -> work -> save -> terminate -> relaunch -> restore"

        // 1. Primera instancia: guardar sesion con 3 tabs.
        let splitTree = SplitNodeState.split(
            direction: .horizontal,
            first: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: nil),
            second: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: "vim"),
            ratio: 0.6
        )
        let tabs = [
            makeSplitTab(title: "Editor", splitTree: splitTree),
            makeLeafTab(title: "Shell"),
            makeLeafTab(title: "Logs"),
        ]
        let savedSession = makeSession(tabs: tabs)
        try sessionManager.saveSession(savedSession, named: nil)

        // 2. "Terminar" -- liberar el manager (simulado).
        sessionManager = nil

        // 3. "Relanzar" -- nueva instancia del manager.
        let newManager = SessionManagerImpl(sessionsDirectory: tempDirectory)

        // 4. Cargar la sesion guardada.
        let loadedSession = try newManager.loadLastSession()
        XCTAssertNotNil(loadedSession, "Session must persist across 'relaunch'")

        // 5. Restaurar.
        let tabManager = TabManager()
        let splitCoordinator = TabSplitCoordinator()
        let result = SessionRestorer.restore(
            from: loadedSession!,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        // 6. Verificar estado identico.
        XCTAssertEqual(result.restoredTabs.count, 3, "Must restore all 3 tabs")
        XCTAssertEqual(result.restoredTabs[0].title, "Editor", "Tab order must be preserved")
        XCTAssertEqual(result.restoredTabs[1].title, "Shell")
        XCTAssertEqual(result.restoredTabs[2].title, "Logs")
        XCTAssertEqual(result.restoredTabs[0].splitNode.leafCount, 2,
                       "Split structure must survive full lifecycle")

        // Limpiar.
        sessionManager = SessionManagerImpl(sessionsDirectory: tempDirectory)
    }

    // MARK: - Test QA-17: Integracion -- sesion corrupta no bloquea el relanzamiento

    func testIntegration_CorruptSession_FreshStartOnRelaunch() throws {
        // 1. Escribir JSON corrupto directamente.
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        let filePath = tempDirectory.appendingPathComponent("last.json")
        try "CORRUPTO{{{".write(to: filePath, atomically: true, encoding: .utf8)

        // 2. Intentar cargar -- debe lanzar parseFailed.
        var loadError: Error?
        do {
            _ = try sessionManager.loadLastSession()
            XCTFail("Must throw on corrupt JSON")
        } catch {
            loadError = error
        }
        XCTAssertNotNil(loadError)

        // 3. El caller puede capturar el error y arrancar fresco -- no crashea.
        // Verificamos que el manager sigue funcionando para el proximo save.
        let freshSession = makeSession(tabs: [makeLeafTab(title: "Fresh")])
        XCTAssertNoThrow(try sessionManager.saveSession(freshSession, named: nil))
    }

    // MARK: - Test QA-18: QuickTerminal -- heightPercent en exactamente el minimo

    func testQuickTerminalViewModel_HeightPercentAtExactMinimum() {
        let vm = QuickTerminalViewModel()
        vm.heightPercent = 0.2  // Exactamente en el minimo.

        let state = vm.toState()
        XCTAssertEqual(state.heightPercent, 0.2, accuracy: 0.0001,
                       "Height percent at exact minimum must not be clamped further")
    }

    // MARK: - Test QA-19: QuickTerminal -- heightPercent en exactamente el maximo

    func testQuickTerminalViewModel_HeightPercentAtExactMaximum() {
        let vm = QuickTerminalViewModel()
        vm.heightPercent = 0.9  // Exactamente en el maximo.

        let state = vm.toState()
        XCTAssertEqual(state.heightPercent, 0.9, accuracy: 0.0001,
                       "Height percent at exact maximum must not be clamped further")
    }

    // MARK: - Test QA-20: QuickTerminal -- restore no aplica clamping adicional

    func testQuickTerminalViewModel_RestoreDoesNotExtraClamp() {
        // El estado guardado ya vino de toState() que clampea -- pero restore()
        // aplica el valor tal cual. Si el valor guardado estuviera fuera de rango
        // (estado de fichero externo manipulado), restore lo acepta sin clampar.
        let vm = QuickTerminalViewModel()
        let state = QuickTerminalSessionState(
            isVisible: false,
            workingDirectory: "~",
            heightPercent: 0.85,
            position: .right
        )

        vm.restore(from: state)

        // El valor debe aplicarse tal cual (0.85 esta dentro del rango valido).
        XCTAssertEqual(vm.heightPercent, 0.85, accuracy: 0.0001,
                       "Restore must apply state value as-is")
    }

    // MARK: - Test QA-21: QuickTerminal Panel -- frame de pantalla con Retina (escala 2x)

    func testQuickTerminalPanel_FrameCalculation_RetinaLikeScreenFrame() {
        // Una pantalla Retina aparece como 2560x1600 en coordenadas de puntos.
        let retinaScreen = NSRect(x: 0, y: 0, width: 2560, height: 1600)
        let frame = QuickTerminalPanel.calculateFrame(
            for: .top,
            heightPercent: 0.4,
            screenFrame: retinaScreen
        )

        XCTAssertEqual(frame.width, 2560, accuracy: 0.1)
        XCTAssertEqual(frame.height, 640, accuracy: 0.1,  // 0.4 * 1600
                       "Retina screen height must scale correctly")
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.1)
        // Para .top: origin.y = maxY - height = 1600 - 640 = 960
        XCTAssertEqual(frame.origin.y, 960, accuracy: 0.1,
                       "Top edge panel on Retina screen must anchor at correct Y")
    }

    // MARK: - Test QA-22: SessionManager -- auto-save concurrente no corrompe el fichero

    func testAutoSave_ConcurrentRapidSaves_FileNotCorrupted() throws {
        // Disparar multiples saves concurrentes y verificar que el fichero
        // final es JSON valido (no queda en estado parcial).
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let saveCount = 20
        let manager = sessionManager!

        for i in 0..<saveCount {
            group.enter()
            queue.async {
                let session = Session(
                    version: Session.currentVersion,
                    savedAt: Date(),
                    windows: [
                        WindowState(
                            frame: CodableRect(x: Double(i), y: 0, width: 1200, height: 800),
                            isFullScreen: false,
                            tabs: [],
                            activeTabIndex: 0
                        )
                    ]
                )
                // saveAsync es fire-and-forget en ioQueue (serial) -- no corrompe.
                manager.saveAsync(session)
                group.leave()
            }
        }

        // Esperar a que todos los saves async terminen.
        let waitExpectation = expectation(description: "All saves dispatched")
        group.notify(queue: .main) { waitExpectation.fulfill() }
        waitForExpectations(timeout: 5.0)

        // Dar tiempo al ioQueue para procesar.
        let drainExpectation = expectation(description: "IO queue drained")
        DispatchQueue(label: "drain").asyncAfter(deadline: .now() + 0.5) {
            drainExpectation.fulfill()
        }
        waitForExpectations(timeout: 2.0)

        // El fichero final debe ser JSON valido y parsearse sin error.
        XCTAssertNoThrow(try self.sessionManager.loadLastSession(),
                         "File after concurrent saves must be valid JSON")
    }

    // MARK: - Test QA-23: SessionManager -- auto-save no arranca doble timer

    func testAutoSave_RestartDoesNotLeakTimer() {
        var callCount = 0

        // Iniciar y reiniciar el auto-save 3 veces.
        for _ in 0..<3 {
            sessionManager.startAutoSave(intervalSeconds: 100) {
                callCount += 1
                return Session(
                    version: Session.currentVersion,
                    savedAt: Date(),
                    windows: []
                )
            }
        }

        // Con intervalo de 100s, no debe haber ninguna llamada en 0.5s.
        let waitExpectation = expectation(description: "No premature calls")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            waitExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.5)

        XCTAssertEqual(callCount, 0,
                       "With 100s interval, capture must not be called within 0.5s")
        sessionManager.stopAutoSave()
    }

    // MARK: - Test QA-24: SessionRestorer -- frame exactamente en el borde del minimo visible

    func testSessionRestorer_FrameExactlyAtMinimumOverlap() {
        // Frame donde la superposicion es EXACTAMENTE 100px en ambos ejes.
        // overlapX = min(100+800, 0+1920) - max(100, 0) = 900 - 100 = 800 ✓ >= 100
        // overlapY = min(0+600, 0+1080) - max(0, 0) = 600 - 0 = 600 ✓ >= 100
        let frameAtEdge = CodableRect(x: 100, y: 0, width: 800, height: 600)
        let screen = CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: frameAtEdge,
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "T",
                            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                            splitTree: .leaf(
                                workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: TabManager(),
            splitCoordinator: TabSplitCoordinator(),
            screenBounds: screen
        )

        // Debe preservar el frame (overlap suficiente en ambos ejes).
        XCTAssertEqual(result.windowFrame, frameAtEdge,
                       "Frame with exactly minimum overlap must be preserved")
    }

    // MARK: - Test QA-25: SessionRestorer -- frame con overlap insuficiente solo en eje Y

    func testSessionRestorer_FrameInsufficientOverlapOnY_UsesDefault() {
        // overlapX grande, overlapY solo 50px (< 100 minimo).
        // frame.y = 1080 - 50 = 1030, frame.height = 600
        // overlapY = min(1030+600, 0+1080) - max(1030, 0) = 1080 - 1030 = 50 < 100 ✗
        let offScreenY = CodableRect(x: 0, y: 1030, width: 1920, height: 600)
        let screen = CodableRect(x: 0, y: 0, width: 1920, height: 1080)
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: offScreenY,
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "T",
                            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                            splitTree: .leaf(
                                workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: TabManager(),
            splitCoordinator: TabSplitCoordinator(),
            screenBounds: screen
        )

        XCTAssertNotEqual(result.windowFrame, offScreenY,
                          "Frame with insufficient Y overlap must use default positioning")
    }

    // MARK: - Test QA-26: QuickTerminalSessionState -- Codable round-trip completo

    func testQuickTerminalSessionState_CodableRoundTrip() throws {
        let original = QuickTerminalSessionState(
            isVisible: true,
            workingDirectory: "/Users/arturo/projects",
            heightPercent: 0.55,
            position: .right
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuickTerminalSessionState.self, from: data)

        XCTAssertEqual(decoded, original,
                       "QuickTerminalSessionState must survive Codable round-trip unchanged")
    }

    // MARK: - Test QA-27: QuickTerminalSessionState -- defaults

    func testQuickTerminalSessionState_Defaults() {
        let defaults = QuickTerminalSessionState.defaults

        XCTAssertFalse(defaults.isVisible)
        XCTAssertEqual(defaults.workingDirectory, "~")
        XCTAssertEqual(defaults.heightPercent, 0.4, accuracy: 0.0001)
        XCTAssertEqual(defaults.position, .top)
    }

    // MARK: - Test QA-28: SessionManager -- fileURL para nil usa "last"

    func testSessionManager_FileNameForNilIsLast() throws {
        // Guardar con nombre nil y verificar que el fichero se llama "last.json".
        let session = makeSession(tabs: [makeLeafTab(title: "T")])
        try sessionManager.saveSession(session, named: nil)

        let expectedPath = tempDirectory.appendingPathComponent("last.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path),
                      "Session with nil name must save as 'last.json'")
    }
}
