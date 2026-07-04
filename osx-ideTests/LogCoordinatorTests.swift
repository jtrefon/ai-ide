import Testing
import Foundation
@testable import osx_ide

final class LogCoordinatorWritesTests {
    let tempDir: URL

    init() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("log-coordinator-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("writeContextLog creates conversation.ndjson with correct content")
    func writeContextLog() async throws {
        let event = ContextLogEvent(
            conversationId: "test-conv",
            source: "chat.user_message",
            content: "Hello from test",
            metadata: ["mode": "coder"]
        )
        await LogCoordinator.writeContextLog(event, projectRoot: tempDir)

        let fileURL = tempDir
            .appendingPathComponent(".ide")
            .appendingPathComponent("logs")
            .appendingPathComponent("conversations")
            .appendingPathComponent("test-conv")
            .appendingPathComponent("conversation.ndjson")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.contains("chat.user_message"))
        #expect(content.contains("Hello from test"))
    }

    @Test("writeToolResult creates executions.ndjson and conversation.ndjson")
    func writeToolResult() async throws {
        let event = ToolResultEvent(
            conversationId: "test-conv-2",
            toolCallId: "call-1",
            toolName: "web_search",
            type: "execute_success",
            input: "query",
            output: "results",
            duration: 1.5,
            metadata: ["resultLength": "100"]
        )
        await LogCoordinator.writeToolResult(event, projectRoot: tempDir)

        let convDir = tempDir
            .appendingPathComponent(".ide")
            .appendingPathComponent("logs")
            .appendingPathComponent("conversations")
            .appendingPathComponent("test-conv-2")

        let execFile = convDir.appendingPathComponent("executions.ndjson")
        #expect(FileManager.default.fileExists(atPath: execFile.path))
        let execContent = try String(contentsOf: execFile, encoding: .utf8)
        #expect(execContent.contains("execute_success"))

        let convFile = convDir.appendingPathComponent("conversation.ndjson")
        #expect(FileManager.default.fileExists(atPath: convFile.path))
        let convContent = try String(contentsOf: convFile, encoding: .utf8)
        #expect(convContent.contains("tool.execute_success"))
    }

    @Test("ContextLogEvent and ToolResultEvent conform to Event")
    func eventConformance() {
        let bus = EventBus()
        let ctx = ContextLogEvent(conversationId: "id", source: "x", content: "x")
        bus.publish(ctx)
        let tool = ToolResultEvent(conversationId: "id", toolCallId: "c", toolName: "t", type: "x")
        bus.publish(tool)
    }
}
