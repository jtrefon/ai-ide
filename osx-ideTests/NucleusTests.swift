//
//  NucleusTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
import Combine
import SwiftUI
@testable import osx_ide

final class NucleusTests: XCTestCase {
    var cancellables = Set<AnyCancellable>()

    // MARK: - EventBus Tests
    
    @MainActor
    func testEventBusPublishSubscribe() {
        let expectation = expectation(description: "Event received")
        let bus = EventBus()
        
        struct TestEvent: Event {
            let value: String
        }
        
        bus.subscribe(to: TestEvent.self) { event in
            XCTAssertEqual(event.value, "test")
            expectation.fulfill()
        }
        .store(in: &cancellables)
        
        bus.publish(TestEvent(value: "test"))
        
        waitForExpectations(timeout: 1.0)
    }
    
    // MARK: - CommandRegistry Tests
    
    @MainActor
    func testCommandRegistryExecution() async throws {
        let registry = CommandRegistry()
        let commandID: CommandID = "test.command"
        var executed = false
        
        registry.register(command: commandID) { _ in
            executed = true
        }
        
        try await registry.execute(commandID)
        XCTAssertTrue(executed, "Command handler should have been executed")
    }
    
    @MainActor
    func testCommandRegistryHijacking() async throws {
        let registry = CommandRegistry()
        let commandID: CommandID = "test.hijack"
        var result = ""
        
        // Initial registration
        registry.register(command: commandID) { _ in
            result = "original"
        }
        
        // Hijack
        registry.register(command: commandID) { _ in
            result = "hijacked"
        }
        
        try await registry.execute(commandID)
        XCTAssertEqual(result, "hijacked", "Last registered handler should win (Hijacking)")
    }
    
    // MARK: - UIRegistry Tests
    
    @MainActor
    func testUIRegistryRegistration() {
        let registry = UIRegistry()
        let point: ExtensionPoint = .sidebarLeft
        
        // Ensure empty initially
        XCTAssertTrue(registry.views(for: point).isEmpty)
        
        // Register view
        registry.register(point: point, name: "TestView", icon: "star", view: Text("Content"))
        
        // Verify
        let views = registry.views(for: point)
        XCTAssertEqual(views.count, 1)
        XCTAssertEqual(views.first?.name, "TestView")
        XCTAssertEqual(views.first?.iconName, "star")
    }
}
