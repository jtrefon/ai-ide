import Foundation
@testable import osx_ide

struct AIToolExecutorTrackingTool: AITool, @unchecked Sendable {
    let name: String
    let description: String = ""
    var parameters: [String: Any] { [:] }

    let tracker: AIToolExecutorConcurrencyTracker
    let delayNs: UInt64

    func execute(arguments _: [String: Any]) async throws -> String {
        await tracker.enter()
        defer { Task { await tracker.exit() } }
        try await Task.sleep(nanoseconds: delayNs)
        return "ok"
    }
}
