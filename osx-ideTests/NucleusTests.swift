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

private actor ToolExecutionMockAIService: AIService {
    private var callCount: Int = 0

    func sendMessage(
        _ request: AIServiceMessageWithProjectRootRequest
    ) async throws -> AIServiceResponse {
        let messages = [ChatMessage(role: .user, content: request.message)]
        return try await sendMessage(AIServiceHistoryRequest(
            messages: messages,
            context: request.context,
            tools: request.tools,
            mode: request.mode,
            projectRoot: request.projectRoot
        ))
    }

    func sendMessage(
        _ request: AIServiceHistoryRequest
    ) async throws -> AIServiceResponse {
        callCount += 1
        if callCount == 1 {
            return AIServiceResponse(
                content: nil,
                toolCalls: [
                    AIToolCall(
                        id: "toolcall_1",
                        name: "create_file",
                        arguments: [
                            "path": "hello_from_test.txt"
                        ])
                ])
        }

        return AIServiceResponse(
            content: "Done.",
            toolCalls: nil
        )
    }

    func explainCode(_ code: String) async throws -> String { "" }
    func refactorCode(_ code: String, instructions: String) async throws -> String { "" }
    func generateCode(_ prompt: String) async throws -> String { "" }
    func fixCode(_ code: String, error: String) async throws -> String { "" }
}

@MainActor
private final class ToolExecutionMockErrorManager: ObservableObject, ErrorManagerProtocol {
    @Published var showErrorAlert: Bool = false
    private(set) var currentError: AppError?

    func handle(_ error: AppError) {
        currentError = error
    }

    func handle(_ error: Error, context: String) {
        currentError = .unknown("\(context): \(error.localizedDescription)")
    }

    func dismissError() {
        currentError = nil
        showErrorAlert = false
    }
}

@MainActor
private final class MockWorkspaceService: ObservableObject, WorkspaceServiceProtocol {
    @Published var currentDirectory: URL?

    func createFile(named name: String, in directory: URL) {}
    func createFolder(named name: String, in directory: URL) {}
    func deleteItem(at url: URL) {}
    func renameItem(at url: URL, to newName: String) -> URL? { nil }
    func navigateToParent() {}
    func navigateTo(subdirectory: String) {}
    func isValidPath(_ path: String) -> Bool { true }
    func makePathValidator(projectRoot: URL) -> PathValidator {
        PathValidator(projectRoot: projectRoot.standardizedFileURL)
    }
    func makePathValidatorForCurrentDirectory() -> PathValidator? {
        guard let currentDirectory else { return nil }
        return makePathValidator(projectRoot: currentDirectory)
    }
    func handleError(_ error: AppError) {}
}

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

    @MainActor
    func testAgentModeExecutesToolCalls() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx-ide-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let errorManager = ToolExecutionMockErrorManager()
        let workspaceService = MockWorkspaceService()
        let eventBus = EventBus()
        let aiService = ToolExecutionMockAIService()

        let conversationManager = ConversationManager(
            dependencies: ConversationManager.Dependencies(
                services: ConversationManager.ServiceDependencies(
                    aiService: aiService,
                    errorManager: errorManager,
                    fileSystemService: FileSystemService(),
                    fileEditorService: nil
                ),
                environment: ConversationManager.EnvironmentDependencies(
                    workspaceService: workspaceService,
                    eventBus: eventBus,
                    projectRoot: projectRoot,
                    codebaseIndex: nil
                )
            )
        )
        conversationManager.currentMode = .agent
        conversationManager.currentInput = "Create a file hello_from_test.txt"
        conversationManager.sendMessage()

        let timeout = Date().addingTimeInterval(5)
        while conversationManager.isSending, Date() < timeout {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(conversationManager.isSending)
        XCTAssertNil(conversationManager.error)

        let createdFile = projectRoot.appendingPathComponent("hello_from_test.txt")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: createdFile.path),
            "Expected tool execution to create hello_from_test.txt"
        )
    }
}
