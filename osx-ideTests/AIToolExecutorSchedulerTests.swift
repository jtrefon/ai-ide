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
}
