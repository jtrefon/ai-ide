import Foundation
protocol ToolExecutor: Sendable { func execute(request: ToolExecutionRequest) async -> ToolFeedback }
