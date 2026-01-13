//
//  TerminalStressTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
import AppKit
@testable import osx_ide

@MainActor
final class TerminalStressTests: XCTestCase {

    private final class NoOpShellManager: ShellManager {
        override func start(in directory: URL? = nil) {
            // No-op in tests: avoid spawning real processes.
        }

        override func sendInput(_ text: String) {
            // No-op
        }

        override func interrupt() {
            // No-op
        }

        override func terminate() {
            // No-op
        }
    }
    
    var embedder: NativeTerminalEmbedder!
    var parentView: NSView!
    private var mockShellManager: NoOpShellManager!
    
    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        mockShellManager = NoOpShellManager()
        embedder = NativeTerminalEmbedder(shellManager: mockShellManager, eventBus: EventBus())
        parentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }
    
    override func tearDown() async throws {
        embedder.removeEmbedding()
        embedder = nil
        mockShellManager = nil
        parentView = nil
        try await super.tearDown()
    }
    
    func testRapidOutputBursts() async throws {
        embedder.embedTerminal(in: parentView)

        // Wait for shell to start
        try await Task.sleep(nanoseconds: 500_000_000)

        // Trigger a command that produces lots of output
        // We can't easily wait for shell manager's internal pipe, so we'll just spam it

        let expectation = expectation(description: "Stress completed without crash")

        // Spam updates (keep bounded to avoid AppKit/test-host instability)
        for outputIndex in 0..<25 {
            // Simulate output from delegate
            // Since didProduceOutput is @MainActor, we can call it directly
            embedder.shellManager(mockShellManager, didProduceOutput: "Output line \(outputIndex)\r\n")

            // Give the main runloop a chance to drain any queued UI updates.
            if outputIndex % 5 == 0 {
                await Task.yield()
            }
        }

        // Wait for all async updates (appendOutput uses DispatchQueue.main.async)
        try await Task.sleep(nanoseconds: 300_000_000)
        expectation.fulfill()

        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    func testRapidReEmbedding() async throws {
        let expectation = expectation(description: "Rapid re-embedding completed")

        for embedIndex in 0..<20 {
            embedder.embedTerminal(in: parentView)
            if embedIndex % 5 == 0 {
                embedder.removeEmbedding()
            }
        }

        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
