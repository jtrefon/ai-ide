import XCTest
import SwiftUI
import Combine
@testable import osx_ide

@MainActor
final class AIToolExecutorSchedulerTests: XCTestCase {
    func testWriteToolsSerializeByPath() async {
        let tracker = ConcurrencyTracker()
        let tool = TrackingTool(name: "write_file", tracker: tracker, delayNs: 200_000_000)

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: NoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let callA = AIToolCall(id: UUID().uuidString, name: "write_file", arguments: ["path": "/tmp/a.txt", "content": "a"])
        let callB = AIToolCall(id: UUID().uuidString, name: "write_file", arguments: ["path": "/tmp/a.txt", "content": "b"])

        _ = await executor.executeBatch([callA, callB], availableTools: [tool], conversationId: nil) { _ in }

        let max = await tracker.maxConcurrent
        XCTAssertEqual(max, 1)
    }

    func testReadToolsRunConcurrently() async {
        let tracker = ConcurrencyTracker()
        let tool = TrackingTool(name: "read_file", tracker: tracker, delayNs: 200_000_000)

        let executor = AIToolExecutor(
            fileSystemService: FileSystemService(),
            errorManager: NoopErrorManager(),
            projectRoot: URL(fileURLWithPath: "/tmp")
        )

        let calls = (0..<3).map { idx in
            AIToolCall(id: UUID().uuidString, name: "read_file", arguments: ["path": "/tmp/file_\(idx).txt"])
        }

        _ = await executor.executeBatch(calls, availableTools: [tool], conversationId: nil) { _ in }

        let max = await tracker.maxConcurrent
        XCTAssertGreaterThanOrEqual(max, 2)
    }
}

private actor ConcurrencyTracker {
    private(set) var current: Int = 0
    private(set) var maxConcurrent: Int = 0

    func enter() {
        current += 1
        if current > maxConcurrent {
            maxConcurrent = current
        }
    }

    func exit() {
        current = max(0, current - 1)
    }
}

private struct TrackingTool: AITool, @unchecked Sendable {
    let name: String
    let description: String = ""
    var parameters: [String: Any] { [:] }

    let tracker: ConcurrencyTracker
    let delayNs: UInt64

    func execute(arguments: [String : Any]) async throws -> String {
        await tracker.enter()
        defer { Task { await tracker.exit() } }
        try await Task.sleep(nanoseconds: delayNs)
        return "ok"
    }
}

@MainActor
private final class NoopErrorManager: ObservableObject, ErrorManagerProtocol {
    @Published var currentError: AppError?
    @Published var showErrorAlert: Bool = false

    func handle(_ error: AppError) {}
    func handle(_ error: Error, context: String) {}
    func dismissError() {}

    var statePublisher: ObservableObjectPublisher {
        objectWillChange
    }
}
