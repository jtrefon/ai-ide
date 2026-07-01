import Foundation
struct RealToolExecutor: ToolExecutor { let registry: ToolRegistryProtocol
    func execute(request: ToolExecutionRequest) async -> ToolFeedback {
        guard let d = registry.tool(named: request.toolName) else { return .error("Unknown: "+request.toolName, code: "UNKNOWN", rec: false) }
        do { return try await d.execute(request) } catch { return .error(error.localizedDescription, code: "EXEC_ERROR") }
    }
}
