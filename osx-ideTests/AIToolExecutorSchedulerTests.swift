import XCTest
import SwiftUI
import Combine
@testable import osx_ide

@MainActor
final class AIToolExecutorSchedulerTests: XCTestCase {
    func testWriteToolsSerializeByPath() async {
        let tracker = AIToolExecutorConcurrencyTracker()
        let tool = AIToolExecutorTrackingTool(name: "write_file", tracker: tracker, delayNs: 200_000_000)

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let callA = AIToolCall(id: UUID().uuidString, name: "write_file", arguments: ["path": "/tmp/a.txt", "content": "a"])
        let callB = AIToolCall(id: UUID().uuidString, name: "write_file", arguments: ["path": "/tmp/a.txt", "content": "b"])

        _ = await executor.executeBatch([callA, callB], availableTools: [tool], conversationId: nil) { _ in () }

        let max = await tracker.maxConcurrent
        XCTAssertEqual(max, 1)
    }

    func testReadToolsRunConcurrently() async {
        let tracker = AIToolExecutorConcurrencyTracker()
        let tool = AIToolExecutorTrackingTool(name: "read_file", tracker: tracker, delayNs: 200_000_000)

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let calls = (0..<3).map { idx in
            AIToolCall(id: UUID().uuidString, name: "read_file", arguments: ["path": "/tmp/file_\(idx).txt"])
        }

        _ = await executor.executeBatch(calls, availableTools: [tool], conversationId: nil) { _ in () }

        let max = await tracker.maxConcurrent
        XCTAssertGreaterThanOrEqual(max, 2)
    }

    func testExecuteBatchReportsExecutingAndCompletedProgress() async {
        let tool = AIToolExecutorTrackingTool(
            name: "read_file",
            tracker: AIToolExecutorConcurrencyTracker(),
            delayNs: 1_000
        )

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let callA = AIToolCall(id: UUID().uuidString, name: "read_file", arguments: ["path": "/tmp/a.txt"])
        let callB = AIToolCall(id: UUID().uuidString, name: "read_file", arguments: ["path": "/tmp/b.txt"])

        var progressMessages: [ChatMessage] = []
        let results = await executor.executeBatch([callA, callB], availableTools: [tool], conversationId: nil) { message in
            progressMessages.append(message)
        }

        XCTAssertEqual(results.count, 2)

        let executing = progressMessages.filter { $0.toolStatus == .executing }
        let completed = progressMessages.filter { $0.toolStatus == .completed }
        XCTAssertEqual(executing.count, 2)
        XCTAssertEqual(completed.count, 2)

        for call in [callA, callB] {
            XCTAssertTrue(executing.contains { $0.toolCallId == call.id && $0.toolName == call.name })
            XCTAssertTrue(completed.contains { $0.toolCallId == call.id && $0.toolName == call.name })
        }

        for result in results {
            XCTAssertEqual(result.role, .tool)
            XCTAssertEqual(result.toolStatus, .completed)
        }
    }

    func testExecuteBatchWithNoToolCallsReturnsEmptyAndReportsNoProgress() async {
        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        var progressMessages: [ChatMessage] = []
        let results = await executor.executeBatch([], availableTools: [], conversationId: nil) { message in
            progressMessages.append(message)
        }

        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(progressMessages.isEmpty)
    }

    func testExecuteBatchWhenToolNotFoundReportsFailure() async {
        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let call = AIToolCall(id: UUID().uuidString, name: "nonexistent_tool", arguments: [:])

        var progressMessages: [ChatMessage] = []
        let results = await executor.executeBatch([call], availableTools: [], conversationId: nil) { message in
            progressMessages.append(message)
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.role, .tool)
        XCTAssertEqual(results.first?.toolName, call.name)
        XCTAssertEqual(results.first?.toolCallId, call.id)
        XCTAssertEqual(results.first?.toolStatus, .failed)

        XCTAssertEqual(progressMessages.count, 2)
        XCTAssertEqual(progressMessages.first?.toolStatus, .executing)
        XCTAssertEqual(progressMessages.last?.toolStatus, .failed)
        XCTAssertEqual(progressMessages.last?.toolCallId, call.id)
    }

    func testExecuteBatchEmitsInvocationPreviewForFileEditTool() async throws {
        let tool = AIToolExecutorTrackingTool(
            name: "replace_in_file",
            tracker: AIToolExecutorConcurrencyTracker(),
            delayNs: 1_000
        )

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let call = AIToolCall(
            id: UUID().uuidString,
            name: "replace_in_file",
            arguments: [
                "path": "/tmp/preview.swift",
                "old_text": "let value = 1",
                "new_text": "let value = 2"
            ]
        )

        var progressMessages: [ChatMessage] = []
        _ = await executor.executeBatch([call], availableTools: [tool], conversationId: nil) { message in
            progressMessages.append(message)
        }

        let executing = try XCTUnwrap(progressMessages.first(where: { $0.toolStatus == .executing }))
        let executingEnvelope = try XCTUnwrap(ToolExecutionEnvelope.decode(from: executing.content))
        XCTAssertNotNil(executingEnvelope.preview)
        XCTAssertTrue(executingEnvelope.preview?.contains("Proposed edit") == true)
        XCTAssertTrue(executingEnvelope.preview?.contains("--- before") == true)
        XCTAssertTrue(executingEnvelope.preview?.contains("+++ after") == true)
    }

    func testExecuteBatchEmitsInvocationPreviewForReadFileRange() async throws {
        let tool = AIToolExecutorTrackingTool(
            name: "read_file",
            tracker: AIToolExecutorConcurrencyTracker(),
            delayNs: 1_000
        )

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: AIToolExecutorNoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let call = AIToolCall(
            id: UUID().uuidString,
            name: "read_file",
            arguments: [
                "path": "/tmp/preview.swift",
                "start_line": 10,
                "end_line": 30
            ]
        )

        var progressMessages: [ChatMessage] = []
        _ = await executor.executeBatch([call], availableTools: [tool], conversationId: nil) { message in
            progressMessages.append(message)
        }

        let executing = try XCTUnwrap(progressMessages.first(where: { $0.toolStatus == .executing }))
        let executingEnvelope = try XCTUnwrap(ToolExecutionEnvelope.decode(from: executing.content))
        XCTAssertNotNil(executingEnvelope.preview)
        XCTAssertTrue(executingEnvelope.preview?.contains("Read file") == true)
        XCTAssertTrue(executingEnvelope.preview?.contains("/tmp/preview.swift") == true)
        XCTAssertTrue(executingEnvelope.preview?.contains("Lines: 10-30") == true)
    }
}
