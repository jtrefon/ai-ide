import Foundation

public protocol AIToolProgressReporting: AITool {
    func execute(
        arguments: [String: Any],
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> String
}
