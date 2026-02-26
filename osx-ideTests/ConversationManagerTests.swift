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
    var mockActivityCoordinator: AgentActivityCoordinator!
    let historyKey = "AIChatHistory"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: historyKey)
        mockAIService = MockAIService()
        mockErrorManager = MockErrorManager()
        mockActivityCoordinator = AgentActivityCoordinator(powerManagementService: MockPowerManagementService())
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()
        let workspaceService = WorkspaceService(
            errorManager: mockErrorManager,
            eventBus: eventBus,
            fileSystemService: fileSystemService
        )
        manager = ConversationManager(
            dependencies: ConversationManager.Dependencies(
                services: ConversationManager.ServiceDependencies(
                    aiService: mockAIService,
                    errorManager: mockErrorManager,
                    fileSystemService: fileSystemService,
                    fileEditorService: nil,
                    activityCoordinator: mockActivityCoordinator
                ),
                environment: ConversationManager.EnvironmentDependencies(
                    workspaceService: workspaceService,
                    eventBus: eventBus,
                    projectRoot: URL(fileURLWithPath: "/tmp"),
                    codebaseIndex: nil
                )
            )
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
        let firstRole = manager.messages.first?.role
        XCTAssertTrue(
            firstRole == .assistant || firstRole == .system,
            "Expected first welcome message role to be assistant or system, got \(String(describing: firstRole))"
        )
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
                    if self.manager.messages.contains(where: {
                        $0.role == MessageRole.assistant && $0.content == "Mock response"
                    }) {
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

    /// Regression guard for the chat panel send path:
    /// verifies an agent-mode input reaches AI service and produces an assistant response.
    func testAgentModeSendMessageRequestResponse() async throws {
        mockAIService.nextHistoryResponse = AIServiceResponse(content: "Agent response", toolCalls: nil)
        manager.currentMode = .agent
        manager.currentInput = "Run in agent mode"

        let agentResponded = expectation(description: "Agent responded")
        agentResponded.assertForOverFulfill = false

        var cancellables = Set<AnyCancellable>()
        manager.objectWillChange
            .sink { _ in
                Task { @MainActor in
                    if self.manager.messages.contains(where: {
                        $0.role == MessageRole.assistant && $0.content == "Agent response"
                    }) {
                        agentResponded.fulfill()
                    }
                }
            }
            .store(in: &cancellables)

        manager.sendMessage()

        await fulfillment(of: [agentResponded], timeout: 5.0)

        let sendingCleared = expectation(description: "Agent sending cleared")
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

        XCTAssertEqual(mockAIService.lastHistoryRequest?.mode, .agent)
        XCTAssertFalse(manager.isSending)
    }

    func testLiveModelOutputPreviewVisibleByDefault() {
        XCTAssertTrue(manager.isLiveModelOutputPreviewVisible)
    }

    func testSendMessageUpdatesLiveModelOutputPreviewWithFinalAssistantResponse() async throws {
        mockAIService.nextHistoryResponse = AIServiceResponse(content: "Preview-ready assistant response", toolCalls: nil)
        manager.currentInput = "Show me output"

        manager.sendMessage()

        let responseExpectation = expectation(description: "Preview updated")
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                let finalAssistantMessage = self.manager.messages.last(where: { $0.role == .assistant && !$0.isDraft })
                if self.manager.isSending == false,
                   let finalAssistantMessage,
                   !finalAssistantMessage.content.isEmpty,
                   self.manager.liveModelOutputPreview == finalAssistantMessage.content {
                    responseExpectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        await fulfillment(of: [responseExpectation], timeout: 3.0)
        let finalAssistantMessage = manager.messages.last(where: { $0.role == .assistant && !$0.isDraft })
        XCTAssertEqual(manager.liveModelOutputPreview, finalAssistantMessage?.content)
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

    func testClearConversationResetsInteractionState() async {
        manager.currentInput = "Work in progress"
        manager.sendMessage()

        // Ensure we hit active sending state before clear
        let sendingExpectation = expectation(description: "Manager entered sending state")
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline {
                if self.manager.isSending {
                    sendingExpectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        await fulfillment(of: [sendingExpectation], timeout: 2.0)

        manager.clearConversation()

        XCTAssertFalse(manager.isSending)
        XCTAssertEqual(manager.currentInput, "")
        XCTAssertEqual(
            manager.messages.last?.content,
            "Conversation cleared. How can I assist you now?"
        )
    }

    func testStopGenerationCancelsInFlightResponse() async {
        mockAIService.responseDelayNanoseconds = 800_000_000
        manager.currentInput = "Long running task"
        manager.sendMessage()

        let sendingExpectation = expectation(description: "Manager entered sending state")
        Task { @MainActor in
            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline {
                if self.manager.isSending {
                    sendingExpectation.fulfill()
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        await fulfillment(of: [sendingExpectation], timeout: 2.0)

        manager.stopGeneration()

        XCTAssertFalse(manager.isSending)
        XCTAssertEqual(manager.liveModelOutputPreview, "Generation stopped by user.")
    }

    func testStartNewConversationCreatesNewTabAndSwitchesToIt() {
        let initialTabCount = manager.conversationTabs.count
        let initialConversationId = manager.currentConversationId

        manager.startNewConversation()

        XCTAssertEqual(manager.conversationTabs.count, initialTabCount + 1)
        XCTAssertNotEqual(manager.currentConversationId, initialConversationId)
        XCTAssertEqual(manager.currentConversationId, manager.conversationTabs.last?.id)
    }

    func testSwitchConversationRestoresPerTabInputStateAndCloseRemovesSession() {
        manager.currentInput = "Session A draft"
        let firstSessionId = manager.currentConversationId

        manager.startNewConversation()
        let secondSessionId = manager.currentConversationId
        manager.currentInput = "Session B draft"

        manager.switchConversation(to: firstSessionId)
        XCTAssertEqual(manager.currentInput, "Session A draft")

        manager.switchConversation(to: secondSessionId)
        XCTAssertEqual(manager.currentInput, "Session B draft")

        manager.closeConversation(id: secondSessionId)
        XCTAssertEqual(manager.currentConversationId, firstSessionId)
        XCTAssertFalse(manager.conversationTabs.contains(where: { $0.id == secondSessionId }))
    }
}

// MARK: - Mocks

final class MockAIService: AIService, @unchecked Sendable {
    var nextHistoryResponse = AIServiceResponse(content: "Mock response", toolCalls: nil)
    var responseDelayNanoseconds: UInt64 = 0
    private(set) var lastHistoryRequest: AIServiceHistoryRequest?

    func sendMessage(
        _ request: AIServiceMessageWithProjectRootRequest
    ) async throws -> AIServiceResponse {
        _ = request
        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        return nextHistoryResponse
    }

    func sendMessage(
        _ request: AIServiceHistoryRequest
    ) async throws -> AIServiceResponse {
        lastHistoryRequest = request
        if responseDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: responseDelayNanoseconds)
        }
        return nextHistoryResponse
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
