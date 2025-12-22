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
    
    var embedder: NativeTerminalEmbedder!
    var parentView: NSView!
    
    override func setUp() async throws {
        try await super.setUp()
        embedder = NativeTerminalEmbedder()
        parentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    }
    
    override func tearDown() async throws {
        embedder.removeEmbedding()
        embedder = nil
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
        
        // Spam many small updates
        for i in 0..<100 {
            // Simulate output from delegate
            // Since didProduceOutput is @MainActor, we can call it directly
            embedder.shellManager(ShellManager(), didProduceOutput: "Output line \(i)\r\n")
            
            if i % 10 == 0 {
                // Occasional ANSI sequences
                embedder.shellManager(ShellManager(), didProduceOutput: "\u{1B}[32mGreen\u{1B}[0m \u{1B}[31mRed\u{1B}[0m\r\n")
            }
        }
        
        // Wait for all async updates (appendOutput uses DispatchQueue.main.async)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testRapidReEmbedding() async throws {
        let expectation = expectation(description: "Rapid re-embedding completed")
        
        for i in 0..<20 {
            embedder.embedTerminal(in: parentView)
            if i % 5 == 0 {
                 embedder.removeEmbedding()
            }
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 2.0)
    }
}
