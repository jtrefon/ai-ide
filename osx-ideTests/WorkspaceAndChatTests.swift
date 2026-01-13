import Testing
import Foundation
@testable import osx_ide

@MainActor
struct WorkspaceAndChatTests {

    private struct ThrowingAIService: AIService {
        func sendMessage(
            _ message: String, 
            context: String?, 
            tools: [AITool]?, 
            mode: AIMode?
        ) async throws -> AIServiceResponse {
            throw NSError(domain: "test.ai", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        func sendMessage(
            _ message: String, 
            context: String?, 
            tools: [AITool]?, 
            mode: AIMode?, 
            projectRoot: URL?
        ) async throws -> AIServiceResponse {
            throw NSError(domain: "test.ai", code: 2, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        func sendMessage(
            _ messages: [ChatMessage], 
            context: String?, 
            tools: [AITool]?, 
            mode: AIMode?, 
            projectRoot: URL?
        ) async throws -> AIServiceResponse {
            throw NSError(domain: "test.ai", code: 3, userInfo: [NSLocalizedDescriptionKey: "boom"])
        }

        func explainCode(_ code: String) async throws -> String { throw NSError(domain: "test.ai", code: 4) }
        func refactorCode(_ code: String, instructions: String) async throws -> String { throw NSError(domain: "test.ai", code: 5) }
        func generateCode(_ prompt: String) async throws -> String { throw NSError(domain: "test.ai", code: 6) }
        func fixCode(_ code: String, error: String) async throws -> String { throw NSError(domain: "test.ai", code: 7) }
    }

    @Test func testErrorHandling() async throws {
        let appState = DependencyContainer().makeAppState()

        appState.lastError = "Test error"

        #expect(appState.lastError == "Unknown error: Test error", "Error should be set")

        appState.lastError = nil
        #expect(appState.lastError == nil, "Error should be clearable")
    }

    @Test func testErrorManagerHandleErrorIncludesContextWhenProvided() async throws {
        let manager = ErrorManager()
        manager.handle(
            NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]), 
            context: "WorkspaceService.rename"
        )

        let description = manager.currentError?.errorDescription ?? ""
        #expect(
            description.contains("WorkspaceService.rename"), 
            "Expected error description to include context"
        )
        #expect(
            description.contains("Test error"), 
            "Expected error description to include underlying message"
        )
    }

    @Test func testErrorManagerHandleErrorDoesNotPrefixEmptyContext() async throws {
        let manager = ErrorManager()
        manager.handle(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"]), context: "")

        let description = manager.currentError?.errorDescription ?? ""
        #expect(description == "Unknown error: Test error", "Expected empty context to not add additional prefixes")
    }

    @Test func testAIServiceSendMessageResultWrapsOperationContext() async throws {
        let service = ThrowingAIService()
        let result = await service.sendMessageResult("hi", context: nil, tools: nil, mode: nil)

        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            let description = error.errorDescription ?? ""
            #expect(description.contains("AIService.sendMessage failed"), "Expected error to include operation context")
        }
    }

    @Test func testChatHistoryManagerSeedsDefaultGreetingOnInit() async throws {
        let expected = "Hello! I'm your AI coding assistant. How can I help you today?"

        let messages = await MainActor.run {
            let manager = ChatHistoryManager()
            return manager.messages
        }

        #expect(messages.count == 1, "Expected a single greeting message")
        #expect(messages.first?.content == expected, "Expected default greeting content")
    }

    @Test func testChatHistoryManagerRestoresDefaultGreetingAfterRemovingAllMessages() async throws {
        let expected = "Hello! I'm your AI coding assistant. How can I help you today?"

        let messages = await MainActor.run {
            let manager = ChatHistoryManager()
            manager.removeOldestMessages(count: manager.messages.count)
            return manager.messages
        }

        #expect(messages.count == 1, "Expected a single greeting message after removal")
        #expect(messages.first?.content == expected, "Expected default greeting content after removal")
    }

    @Test func testWorkspaceServiceRenamePublishesEventAndMovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let workspaceService = WorkspaceService(errorManager: errorManager, eventBus: eventBus)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_workspace_rename_\(UUID().uuidString)")
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

        let newURL = workspaceService.renameItem(at: file, to: "b.txt")
        #expect(newURL != nil, "Expected rename to return new URL")

        #expect(!FileManager.default.fileExists(atPath: file.path), "Expected old path to be gone")
        #expect(FileManager.default.fileExists(atPath: newURL!.path), "Expected new path to exist")

        #expect(capturedOld?.standardizedFileURL.path == file.standardizedFileURL.path, "Expected event oldUrl to match")
        #expect(capturedNew?.standardizedFileURL.path == newURL!.standardizedFileURL.path, "Expected event newUrl to match")
    }

    @Test func testWorkspaceServiceDeletePublishesEventAndRemovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let workspaceService = WorkspaceService(errorManager: errorManager, eventBus: eventBus)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_workspace_delete_\(UUID().uuidString)")
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

        workspaceService.deleteItem(at: file)

        #expect(!FileManager.default.fileExists(atPath: file.path), "Expected file to be removed from original location")
        #expect(capturedDeleted?.standardizedFileURL.path == file.standardizedFileURL.path, "Expected delete event to reference the removed file")
    }
}
