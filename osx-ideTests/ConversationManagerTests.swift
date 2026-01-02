//
//  ConversationManagerTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
import Combine
@testable import osx_ide

@MainActor
final class ConversationManagerTests: XCTestCase {
    
    var manager: ConversationManager!
    var mockAIService: MockAIService!
    var mockErrorManager: MockErrorManager!
    let historyKey = "AIChatHistory"
    
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: historyKey)
        mockAIService = MockAIService()
        mockErrorManager = MockErrorManager()
        manager = ConversationManager(
            aiService: mockAIService,
            errorManager: mockErrorManager,
            projectRoot: URL(fileURLWithPath: "/tmp")
        )
    }
    
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: historyKey)
        manager = nil
        mockAIService = nil
        mockErrorManager = nil
        try await super.tearDown()
    }
    
    func testWelcomeMessage() {
        XCTAssertTrue(manager.messages.count >= 1)
        XCTAssertEqual(manager.messages.first?.role, .assistant)
    }
    
    func testSendMessageFlow() async throws {
        manager.currentInput = "Hello AI"
        
        let aiResponded = expectation(description: "AI responded")
        aiResponded.assertForOverFulfill = false
        
        // Observe manager's objectWillChange to wait for response
        var cancellables = Set<AnyCancellable>()
        manager.objectWillChange
            .sink { _ in
                // Using a small delay to allow state to actually change after notification
                Task { @MainActor in
                    if self.manager.messages.contains(where: { $0.role == .assistant && $0.content == "Mock response" }) {
                        aiResponded.fulfill()
                    }
                }
            }
            .store(in: &cancellables)
        
        manager.sendMessage()
        
        await fulfillment(of: [aiResponded], timeout: 5.0)

        let sendingCleared = self.expectation(description: "Sending cleared")
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if self.manager.isSending == false {
                    sendingCleared.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        await fulfillment(of: [sendingCleared], timeout: 3.0)
        XCTAssertFalse(manager.isSending)
    }

    func testSplitReasoningExtractsAndStripsBlock() {
        let input = """
        <ide_reasoning>
        Analyze: A
        Research: B
        Plan: C
        Reflect: D
        </ide_reasoning>

        Hello world.
        """

        let result = ChatPromptBuilder.splitReasoning(from: input)
        XCTAssertEqual(result.content, "Hello world.")
        XCTAssertNotNil(result.reasoning)
        XCTAssertTrue((result.reasoning ?? "").contains("Analyze:"))
        XCTAssertTrue((result.reasoning ?? "").contains("Reflect:"))
    }
}

// MARK: - Mocks

final class MockAIService: AIService, @unchecked Sendable {
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse {
        return AIServiceResponse(content: "Mock response", toolCalls: nil)
    }
    
    func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        return AIServiceResponse(content: "Mock response", toolCalls: nil)
    }
    
    func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse {
        return AIServiceResponse(content: "Mock response", toolCalls: nil)
    }
    
    func explainCode(_ code: String) async throws -> String { return "Explanation" }
    func refactorCode(_ code: String, instructions: String) async throws -> String { return "Refactored" }
    func generateCode(_ prompt: String) async throws -> String { return "Generated" }
    func fixCode(_ code: String, error: String) async throws -> String { return "Fixed" }
}

final class MockErrorManager: ObservableObject, ErrorManagerProtocol {
    @Published var currentError: AppError?
    @Published var showErrorAlert: Bool = false
    
    func handle(_ error: AppError) { self.currentError = error }
    func handle(_ error: Error, context: String) { }
    func dismissError() { self.showErrorAlert = false }
    
    var statePublisher: ObservableObjectPublisher {
        return self.objectWillChange
    }
}
