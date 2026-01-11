import Foundation

public protocol AIToolProgressReporting: AITool {
    func execute(
        arguments: ToolArguments,
        onProgress: @Sendable @escaping (String) -> Void
    ) async throws -> String
}
