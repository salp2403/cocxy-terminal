// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PortScannerTests.swift - Tests for localhost port scanning.

import XCTest
import Combine
@testable import CocxyTerminal

@MainActor
final class PortScannerTests: XCTestCase {

    // MARK: - DetectedPort Model Tests

    func testDetectedPortInitialization() {
        let port = DetectedPort(port: 3000, processName: "node")
        XCTAssertEqual(port.port, 3000)
        XCTAssertEqual(port.processName, "node")
    }

    func testDetectedPortIDIsPortNumber() {
        let port = DetectedPort(port: 8080, processName: nil)
        XCTAssertEqual(port.id, 8080)
    }

    func testDetectedPortEquality() {
        let a = DetectedPort(port: 3000, processName: "node")
        let b = DetectedPort(port: 3000, processName: "node")
        XCTAssertEqual(a, b)
    }

    func testDetectedPortInequalityByPort() {
        let a = DetectedPort(port: 3000, processName: "node")
        let b = DetectedPort(port: 8080, processName: "node")
        XCTAssertNotEqual(a, b)
    }

    func testDetectedPortInequalityByProcessName() {
        let a = DetectedPort(port: 3000, processName: "node")
        let b = DetectedPort(port: 3000, processName: "python")
        XCTAssertNotEqual(a, b)
    }

    func testDetectedPortNilProcessName() {
        let port = DetectedPort(port: 5173, processName: nil)
        XCTAssertNil(port.processName)
        XCTAssertEqual(port.port, 5173)
    }

    // MARK: - PortScannerImpl Tests

    func testDefaultPortsNotEmpty() {
        XCTAssertFalse(PortScannerImpl.defaultPorts.isEmpty)
    }

    func testDefaultPortsContainCommonDevPorts() {
        let ports = PortScannerImpl.defaultPorts
        XCTAssertTrue(ports.contains(3000), "Should include Next.js default port")
        XCTAssertTrue(ports.contains(8080), "Should include common HTTP port")
        XCTAssertTrue(ports.contains(5173), "Should include Vite default port")
    }

    func testScannerStartsSetsIsScanning() {
        let scanner = PortScannerImpl()
        XCTAssertFalse(scanner.isScanning)
        scanner.startScanning(interval: 60.0) // Long interval to avoid actual scans
        XCTAssertTrue(scanner.isScanning)
        scanner.stopScanning()
    }

    func testScannerStopClearsIsScanning() {
        let scanner = PortScannerImpl()
        scanner.startScanning(interval: 60.0)
        scanner.stopScanning()
        XCTAssertFalse(scanner.isScanning)
    }

    func testScannerDoubleStartReplacesTimer() {
        let scanner = PortScannerImpl()
        scanner.startScanning(interval: 60.0)
        XCTAssertTrue(scanner.isScanning)
        scanner.startScanning(interval: 30.0) // Replace
        XCTAssertTrue(scanner.isScanning)
        scanner.stopScanning()
    }

    func testScannerInitialActivePortsEmpty() {
        let scanner = PortScannerImpl()
        XCTAssertTrue(scanner.activePorts.isEmpty)
    }

    func testScanOnceReturnsArray() async {
        let scanner = PortScannerImpl()
        let result = await scanner.scanOnce()
        // Result is valid (may be empty or contain ports depending on machine state)
        XCTAssertNotNil(result)
        // Verify sorted order
        for i in 0..<max(0, result.count - 1) {
            XCTAssertLessThanOrEqual(result[i].port, result[i + 1].port)
        }
    }

    func testActivePortsSortedByPortNumber() async {
        let scanner = PortScannerImpl()
        _ = await scanner.scanOnce()
        let ports = scanner.activePorts
        for i in 0..<max(0, ports.count - 1) {
            XCTAssertLessThanOrEqual(ports[i].port, ports[i + 1].port)
        }
    }

    func testStopScanningAfterDealloc() {
        var scanner: PortScannerImpl? = PortScannerImpl()
        scanner?.startScanning(interval: 60.0)
        XCTAssertTrue(scanner?.isScanning ?? false)
        scanner = nil
        // No crash = success
    }
}
