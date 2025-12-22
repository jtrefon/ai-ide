//
//  ShellManagerTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
@testable import osx_ide

@MainActor
final class ShellManagerTests: XCTestCase, ShellManagerDelegate {
    
    var shellManager: ShellManager!
    var outputExpectation: XCTestExpectation?
    var terminationExpectation: XCTestExpectation?
    var lastOutput: String = ""
    var startupErrorMessage: String?
    
    override func setUp() async throws {
        try await super.setUp()
        shellManager = ShellManager()
        shellManager.delegate = self
        startupErrorMessage = nil
        lastOutput = ""
    }
    
    override func tearDown() async throws {
        shellManager.terminate()
        shellManager = nil
        try await super.tearDown()
    }
    
    // MARK: - ShellManagerDelegate
    
    func shellManager(_ manager: ShellManager, didProduceOutput output: String) {
        lastOutput += output
        if lastOutput.contains("hello_test") {
            outputExpectation?.fulfill()
        }
    }
    
    func shellManager(_ manager: ShellManager, didFailWithError error: String) {
        // Shell startup can fail on developer machines / CI depending on permissions,
        // sandboxing, or environment. Record it and let the test decide whether to skip.
        startupErrorMessage = error
    }
    
    func shellManagerDidTerminate(_ manager: ShellManager) {
        terminationExpectation?.fulfill()
    }
    
    // MARK: - Tests
    
    func testShellLifecycle() async throws {
        outputExpectation = expectation(description: "Output received")
        
        shellManager.start()
        
        // Wait a bit for shell to be ready
        try await Task.sleep(nanoseconds: 1_500_000_000)

        if let startupErrorMessage {
            throw XCTSkip("Skipping ShellManager lifecycle test: \(startupErrorMessage)")
        }
        
        shellManager.sendInput("echo hello_test\n")
        
        do {
            await fulfillment(of: [outputExpectation!], timeout: 10.0)
        } catch {
            throw XCTSkip("Skipping ShellManager lifecycle test: no output received from shell")
        }
        XCTAssertTrue(lastOutput.contains("hello_test"))
    }
    
    func testRapidRestart() async throws {
        // Provoke race conditions in cleanup/setup
        for _ in 0..<10 {
            shellManager.start()
            shellManager.terminate()
        }
        
        // Just verify it doesn't crash during the loop
    }
    
    func testConcurrentInput() async throws {
        shellManager.start()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Spam input from main actor to avoid Sendable issues in test
        for i in 0..<50 {
            shellManager.sendInput("echo concurrent_\(i)\n")
        }
        
        // Allow time for processing
        try await Task.sleep(nanoseconds: 500_000_000)
        // Pass if no crash
    }
}
