import XCTest
import Foundation
@testable import osx_ide

@MainActor
final class WorkspaceAndChatTests: XCTestCase {

    private struct ThrowingAIService: AIService {
        func sendMessage(
            _ request: AIServiceMessageWithProjectRootRequest
        ) async throws -> AIServiceResponse {
            _ = request
            throw NSError(domain: "test.ai", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        func sendMessage(
            _ request: AIServiceHistoryRequest
        ) async throws -> AIServiceResponse {
            _ = request
            throw NSError(domain: "test.ai", code: 2, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            try await sendMessage(request)
        }
    }

    func testErrorHandling() async throws {
        let appState = DependencyContainer().makeAppState()

        appState.lastError = "Test error"

        XCTAssertEqual(appState.lastError, "Unknown error: Test error", "Error should be set")

        appState.lastError = nil
        XCTAssertNil(appState.lastError, "Error should be clearable")
    }

    func testErrorManagerHandleErrorIncludesContextWhenProvided() async throws {
        let manager = ErrorManager()
        manager.handle(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]),
            context: "WorkspaceService.rename"
        )

        let description = manager.currentError?.errorDescription ?? ""
        XCTAssertTrue(
            description.contains("WorkspaceService.rename"),
            "Expected error description to include context"
        )
        XCTAssertTrue(
            description.contains("Test error"),
            "Expected error description to include underlying message"
        )
    }

    func testErrorManagerHandleErrorDoesNotPrefixEmptyContext() async throws {
        let manager = ErrorManager()
        manager.handle(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]),
            context: ""
        )

        let description = manager.currentError?.errorDescription ?? ""
        XCTAssertEqual(description, "Unknown error: Test error", "Expected empty context to not add additional prefixes")
    }

    func testAIServiceSendMessageResultWrapsOperationContext() async throws {
        let service = ThrowingAIService()
        let result = await service.sendMessageResult("hi", context: nil, tools: nil, mode: nil)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            let description = error.errorDescription ?? ""
            XCTAssertTrue(description.contains("AIService.sendMessage failed"), "Expected error to include operation context")
        }
    }

    func testChatHistoryCoordinatorStartsEmpty() async throws {
        let coordinator = await MainActor.run {
            ChatHistoryCoordinator(projectRoot: FileManager.default.temporaryDirectory)
        }
        let messages = await coordinator.messages
        XCTAssertEqual(messages.count, 0, "Expected empty coordinator")
    }

    func testChatHistoryCoordinatorAppendsMessages() async throws {
        let coordinator = await MainActor.run {
            ChatHistoryCoordinator(projectRoot: FileManager.default.temporaryDirectory)
        }
        await MainActor.run {
            coordinator.append(ChatMessage(role: .user, content: "test"))
        }
        let messages = await coordinator.messages
        XCTAssertEqual(messages.count, 1, "Expected one message after append")
        XCTAssertEqual(messages.first?.content, "test")
    }

    func testWorkspaceServiceRenamePublishesEventAndMovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()
        let workspaceService = WorkspaceService(
            errorManager: errorManager,
            eventBus: eventBus,
            fileSystemService: fileSystemService
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_workspace_rename_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        workspaceService.currentDirectory = tempRoot

        let file = tempRoot.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        var capturedOld: URL?
        var capturedNew: URL?
        let cancellable = eventBus.subscribe(to: FileRenamedEvent.self) { event in
            capturedOld = event.oldUrl
            capturedNew = event.newUrl
        }
        _ = cancellable

        let newURL = await workspaceService.renameItem(at: file, to: "b.txt")
        XCTAssertNotNil(newURL, "Expected rename to return new URL")

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Expected old path to be gone")
        guard let newURL else {
            XCTFail("Expected rename to return new URL")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path), "Expected new path to exist")

        // Wait for async events to be delivered on main thread
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertEqual(capturedOld?.standardizedFileURL.path, file.standardizedFileURL.path, "Expected event oldUrl to match")
        XCTAssertEqual(capturedNew?.standardizedFileURL.path, newURL.standardizedFileURL.path, "Expected event newUrl to match")
    }

    func testWorkspaceServiceDeletePublishesEventAndRemovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let fileSystemService = FileSystemService()
        let workspaceService = WorkspaceService(
            errorManager: errorManager,
            eventBus: eventBus,
            fileSystemService: fileSystemService
        )

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_workspace_delete_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        workspaceService.currentDirectory = tempRoot

        let file = tempRoot.appendingPathComponent("delete_me.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        var capturedDeleted: URL?
        let cancellable = eventBus.subscribe(to: FileDeletedEvent.self) { event in
            capturedDeleted = event.url
        }
        _ = cancellable

        await workspaceService.deleteItem(at: file)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "Expected file to be removed from original location"
        )
        
        // Wait for async events to be delivered on main thread
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        XCTAssertEqual(
            capturedDeleted?.standardizedFileURL.path, file.standardizedFileURL.path,
            "Expected delete event to reference the removed file"
        )
    }
}
