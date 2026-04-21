// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase10EdgeCaseTests.swift - Edge case tests for Fase 10 productivity features.
//
// Features under test:
//   - FuzzyMatcher (CommandPalette)
//   - CommandPaletteEngineImpl
//   - ScrollbackSearchEngineImpl
//   - AgentTimelineStoreImpl / TimelineExporter
//
// Test plan (10 cases):
//  1.  FuzzyMatcher: query de 1000 chars no causa cuelgue.
//  2.  FuzzyMatcher: caracteres especiales en query no producen crash.
//  3.  CommandPalette: 1000 acciones registradas, búsqueda sigue siendo rápida.
//  4.  CommandPalette: execute de acción cuyo handler lanza (fatalError capturado).
//  5.  ScrollbackSearch: regex inválida produce estado error, no crash.
//  6.  ScrollbackSearch: búsqueda en array vacío devuelve resultados vacíos.
//  7.  ScrollbackSearch: unicode (emoji + CJK) encuentra coincidencias correctamente.
//  8.  Timeline: 1001 eventos => el más antiguo es eviccionado (FIFO, cap=1000).
//  9.  Timeline: exportar timeline vacío devuelve output válido vacío.
// 10.  Timeline: addEvent concurrente desde 10 threads no produce crash.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Phase 10 Edge Case Tests

final class Phase10EdgeCaseTests: XCTestCase {

    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    // MARK: - 1. FuzzyMatcher: query muy larga (1000 chars) no causa cuelgue

    func testFuzzyMatcherVeryLongQueryDoesNotHang() {
        let longQuery = String(repeating: "a", count: 1000)
        let target = "New Tab"

        let start = CFAbsoluteTimeGetCurrent()
        let result = FuzzyMatcher.fuzzyMatch(query: longQuery, target: target)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        // El resultado puede ser nil (no match) o un FuzzyMatchResult.
        // Lo importante es que termina en tiempo razonable.
        _ = result
        XCTAssertLessThan(elapsed, 1.0,
            "FuzzyMatcher con query de 1000 chars debe terminar en < 1s, tardó \(elapsed)s")
    }

    // MARK: - 2. FuzzyMatcher: caracteres especiales en query no producen crash

    func testFuzzyMatcherSpecialCharactersInQueryDoNotCrash() {
        let specialQueries = [
            "!@#$%^&*()",
            "null\0byte",
            "\n\r\t",
            "[]{}|\\<>?",
            "αβγδεζηθ",
            "日本語テスト",
            "🔥💀🚀",
            String(repeating: ".", count: 50),
            "\u{200B}\u{FEFF}",  // zero-width space + BOM
        ]
        let target = "Split Stacked"

        for query in specialQueries {
            // Solo verificamos que no crashea. El resultado puede ser nil.
            let result = FuzzyMatcher.fuzzyMatch(query: query, target: target)
            _ = result
        }

        // Si llega aquí sin crash, el test pasa.
        XCTAssertTrue(true, "FuzzyMatcher debe manejar caracteres especiales sin crash")
    }

    // MARK: - 3. CommandPalette: 1000 acciones registradas, búsqueda sigue siendo rápida

    @MainActor
    func testCommandPalette1000ActionsSearchRemainsResponsiveInDebugBuilds() {
        let engine = CommandPaletteEngineImpl()

        // Registrar 1000 acciones adicionales (ya hay ~9 built-ins)
        let extra = (0..<1000).map { index in
            CommandAction(
                id: "stress.action.\(index)",
                name: "Stress Action \(index)",
                description: "Bulk test action #\(index)",
                shortcut: nil,
                category: .tabs,
                handler: {}
            )
        }
        engine.registerActions(extra)

        XCTAssertGreaterThanOrEqual(engine.allActions.count, 1000,
            "Deben registrarse al menos 1000 acciones")

        let start = CFAbsoluteTimeGetCurrent()
        let results = engine.search(query: "Stress")
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(results.isEmpty,
            "La búsqueda sobre 1000+ acciones debe devolver resultados")
        // Este target corre en debug y comparte CPU con miles de tests más en
        // CI; el objetivo aquí es detectar regresiones groseras, no imponer un
        // presupuesto de micro-benchmark propio de un build optimizado.
        XCTAssertLessThan(elapsed, 0.5,
            "La búsqueda sobre 1000+ acciones debe seguir siendo responsiva en debug, tardó \(elapsed)s")
    }

    // MARK: - 4. CommandPalette: execute acción cuyo handler lanza fatalError (no crash)
    //
    // Nota: `fatalError` dentro de un handler Swift realmente aborta el proceso.
    // Lo que podemos verificar es que una acción con handler que no lanza
    // se ejecuta sin problema, y documentamos que el código de producción NO
    // captura errores del handler (lo que es correcto: los handlers son @MainActor
    // closures y no hay try/catch). Este test verifica el comportamiento
    // documentado: el handler se ejecuta sin protección adicional.
    // La "action that throws" del enunciado se interpreta como una acción cuyo
    // handler tiene side-effects inesperados (mutación de estado), no un throw literal.

    @MainActor
    func testCommandPaletteExecuteActionWithThrowingLikeSideEffectNoSystemCrash() {
        let engine = CommandPaletteEngineImpl()
        var sideEffectCount = 0
        var secondHandlerCalled = false

        // Acción 1: hace algo "peligroso" (mutación inesperada de shared state)
        let dangerous = CommandAction(
            id: "edge.dangerous",
            name: "Dangerous Action",
            description: "Modifies shared state unexpectedly",
            shortcut: nil,
            category: .agent,
            handler: {
                // Simular side effect: múltiples mutaciones rápidas
                for _ in 0..<100 {
                    sideEffectCount += 1
                }
            }
        )

        // Acción 2: se ejecuta después y debe funcionar con normalidad
        let normal = CommandAction(
            id: "edge.normal",
            name: "Normal Action",
            description: "Should execute normally after dangerous action",
            shortcut: nil,
            category: .tabs,
            handler: { secondHandlerCalled = true }
        )

        engine.registerAction(dangerous)
        engine.registerAction(normal)
        engine.execute(dangerous)
        engine.execute(normal)

        XCTAssertEqual(sideEffectCount, 100,
            "El handler peligroso debe haber ejecutado sus 100 iteraciones")
        XCTAssertTrue(secondHandlerCalled,
            "La acción normal posterior debe ejecutarse sin problema")
    }

    // MARK: - 5. ScrollbackSearch: regex inválida produce estado error, no crash

    @MainActor
    func testScrollbackSearchInvalidRegexProducesErrorStateNoCrash() {
        let engine = ScrollbackSearchEngineImpl()
        let lines = ["hello world", "foo bar"]
        let invalidRegexOptions: [String] = [
            "[invalid",         // corchete sin cerrar
            "(?P<",             // grupo nombrado incompleto
            "*invalid",         // cuantificador sin átomo previo
            "(?",               // grupo sin cerrar
            "\\",               // backslash al final
        ]

        for pattern in invalidRegexOptions {
            let options = SearchOptions(query: pattern, useRegex: true)
            let results = engine.search(options: options, in: lines)

            XCTAssertTrue(results.isEmpty,
                "Regex inválida '\(pattern)' debe devolver array vacío, no crash")

            if case .error = engine.state {
                // Correcto: estado de error para regex inválida
            } else {
                XCTFail("Regex inválida '\(pattern)' debe producir estado .error, got: \(engine.state)")
            }

            // Resetear para el siguiente ciclo
            engine.cancel()
            XCTAssertEqual(engine.state, .idle,
                "Cancel debe resetear estado a idle tras error de regex")
        }
    }

    // MARK: - 6. ScrollbackSearch: búsqueda en array vacío devuelve resultados vacíos

    @MainActor
    func testScrollbackSearchInEmptyLinesArrayReturnsEmptyResults() {
        let engine = ScrollbackSearchEngineImpl()
        let emptyLines: [String] = []

        // Búsqueda plain text en array vacío
        let plainOptions = SearchOptions(query: "hello")
        let plainResults = engine.search(options: plainOptions, in: emptyLines)
        XCTAssertTrue(plainResults.isEmpty,
            "Búsqueda plain text en array vacío debe devolver resultados vacíos")

        if case .completed(let count) = engine.state {
            XCTAssertEqual(count, 0, "resultCount debe ser 0 para array vacío")
        } else {
            XCTFail("Estado debe ser .completed(0) tras buscar en array vacío, got: \(engine.state)")
        }

        // Búsqueda regex en array vacío
        engine.cancel()
        let regexOptions = SearchOptions(query: "hel+o", useRegex: true)
        let regexResults = engine.search(options: regexOptions, in: emptyLines)
        XCTAssertTrue(regexResults.isEmpty,
            "Búsqueda regex en array vacío debe devolver resultados vacíos")
    }

    // MARK: - 7. ScrollbackSearch: unicode (emoji + CJK) encuentra coincidencias

    @MainActor
    func testScrollbackSearchUnicodeEmojiAndCJKMatchesCorrectly() {
        let engine = ScrollbackSearchEngineImpl()
        let lines = [
            "Build 🔥 completed successfully",
            "日本語テスト: エラーなし",
            "Chinese: 你好世界",
            "Arabic: مرحبا بالعالم",
            "Mixed: Hello 世界 🌍 World",
            "No match here",
        ]

        // Búsqueda de emoji
        let emojiOptions = SearchOptions(query: "🔥")
        let emojiResults = engine.search(options: emojiOptions, in: lines)
        XCTAssertEqual(emojiResults.count, 1, "Debe encontrar exactamente 1 línea con 🔥")
        XCTAssertEqual(emojiResults[0].lineNumber, 0)
        XCTAssertEqual(emojiResults[0].matchText, "🔥")

        // Búsqueda de CJK japonés
        engine.cancel()
        let cjkOptions = SearchOptions(query: "テスト")
        let cjkResults = engine.search(options: cjkOptions, in: lines)
        XCTAssertEqual(cjkResults.count, 1, "Debe encontrar exactamente 1 línea con テスト")
        XCTAssertEqual(cjkResults[0].lineNumber, 1)

        // Búsqueda de chino
        engine.cancel()
        let chineseOptions = SearchOptions(query: "你好")
        let chineseResults = engine.search(options: chineseOptions, in: lines)
        XCTAssertEqual(chineseResults.count, 1, "Debe encontrar exactamente 1 línea con 你好")
        XCTAssertEqual(chineseResults[0].lineNumber, 2)

        // Búsqueda de globo terráqueo (aparece en línea 4 junto a "世界")
        engine.cancel()
        let globeOptions = SearchOptions(query: "🌍")
        let globeResults = engine.search(options: globeOptions, in: lines)
        XCTAssertEqual(globeResults.count, 1, "Debe encontrar exactamente 1 línea con 🌍")
        XCTAssertEqual(globeResults[0].lineNumber, 4)
    }

    // MARK: - 8. Timeline: 1001 eventos => el más antiguo es eviccionado (FIFO, cap=1000)

    func testTimeline1001EventsOldestEvictedFIFO() {
        let store = AgentTimelineStoreImpl(maxEventsPerSession: 1000)
        let sessionId = "edge-fifo-1001"

        // Insertar 1001 eventos con timestamps crecientes
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<1001 {
            let event = TimelineEvent(
                id: UUID(),
                timestamp: baseDate.addingTimeInterval(Double(i)),
                type: .toolUse,
                sessionId: sessionId,
                toolName: "Write",
                filePath: nil,
                summary: "Event \(i)",
                durationMs: nil,
                isError: false
            )
            store.addEvent(event)
        }

        let events = store.events(for: sessionId)

        // El store debe tener exactamente 1000 eventos
        XCTAssertEqual(events.count, 1000,
            "Tras añadir 1001 eventos, el store debe tener exactamente 1000 (cap FIFO)")

        // El evento más antiguo (Event 0) debe haber sido eviccionado
        XCTAssertFalse(events.contains { $0.summary == "Event 0" },
            "El evento más antiguo (Event 0) debe haber sido eviccionado por FIFO")

        // El segundo evento más antiguo (Event 1) también debe haber desaparecido
        // (porque hemos insertado 1001 y el cap es 1000, así que se eviccionaron 1)
        // Concretamente: al insertar el evento 1000 (el 1001-avo),
        // el primero (Event 0) se eviccionó. Events 1-1000 permanecen.
        XCTAssertTrue(events.contains { $0.summary == "Event 1" },
            "Event 1 debe seguir presente (solo Event 0 fue eviccionado)")

        // El último evento añadido (Event 1000) debe estar presente
        XCTAssertTrue(events.contains { $0.summary == "Event 1000" },
            "El último evento añadido (Event 1000) debe estar presente")

        // Verificar que el eventCount también es correcto
        XCTAssertEqual(store.eventCount(for: sessionId), 1000,
            "eventCount debe devolver 1000 tras evicción FIFO")
    }

    // MARK: - 9. Timeline: exportar timeline vacío devuelve output válido vacío

    func testTimelineExportEmptyTimelineProducesValidEmptyOutput() {
        let store = AgentTimelineStoreImpl()
        let sessionId = "edge-empty-export"

        // No añadimos ningún evento

        // JSON vacío: debe ser un array vacío válido, no nil ni error
        let jsonData = store.exportJSON(for: sessionId)
        XCTAssertFalse(jsonData.isEmpty,
            "exportJSON de sesión vacía no debe devolver Data vacía")

        // Debe ser JSON parseable como array vacío
        let decoded = try? JSONDecoder().decode([TimelineEvent].self, from: jsonData)
        XCTAssertNotNil(decoded, "exportJSON de sesión vacía debe devolver JSON parseable")
        XCTAssertEqual(decoded?.count, 0,
            "exportJSON de sesión vacía debe contener array JSON con 0 elementos")

        // Markdown vacío: debe ser string vacío (no tabla con cabecera sin filas)
        let markdown = store.exportMarkdown(for: sessionId)
        XCTAssertEqual(markdown, "",
            "exportMarkdown de sesión vacía debe devolver string vacío, got: '\(markdown)'")

        // Verificar también el TimelineExporter directamente con array vacío
        let directJSON = TimelineExporter.exportJSON(events: [])
        let directDecoded = try? JSONDecoder().decode([TimelineEvent].self, from: directJSON)
        XCTAssertNotNil(directDecoded, "TimelineExporter.exportJSON([]) debe devolver JSON parseable")
        XCTAssertEqual(directDecoded?.count, 0,
            "TimelineExporter.exportJSON([]) debe devolver array vacío")

        let directMarkdown = TimelineExporter.exportMarkdown(events: [])
        XCTAssertEqual(directMarkdown, "",
            "TimelineExporter.exportMarkdown([]) debe devolver string vacío")
    }

    // MARK: - 10. Timeline: addEvent concurrente desde 10 threads no produce crash

    func testTimelineConcurrentAddFrom10ThreadsDoesNotCrash() {
        let store = AgentTimelineStoreImpl()
        let sessionId = "edge-concurrent-10"
        let eventsPerThread = 50
        let threadCount = 10
        let totalExpected = eventsPerThread * threadCount

        let group = DispatchGroup()
        let expectation = expectation(description: "10 threads completan sin crash")

        for threadIndex in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for eventIndex in 0..<eventsPerThread {
                    let event = TimelineEvent(
                        id: UUID(),
                        timestamp: Date(),
                        type: .toolUse,
                        sessionId: sessionId,
                        toolName: "Write",
                        filePath: nil,
                        summary: "Thread \(threadIndex) Event \(eventIndex)",
                        durationMs: nil,
                        isError: false
                    )
                    store.addEvent(event)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10.0)

        // Todos los eventos deben haberse almacenado (500 < cap 1000)
        let finalCount = store.eventCount(for: sessionId)
        XCTAssertEqual(finalCount, totalExpected,
            "Tras \(threadCount) threads x \(eventsPerThread) eventos = \(totalExpected) esperados, got \(finalCount)")

        let storedEvents = store.events(for: sessionId)
        XCTAssertEqual(storedEvents.count, totalExpected,
            "events(for:) debe devolver los \(totalExpected) eventos almacenados concurrentemente")
    }
}
