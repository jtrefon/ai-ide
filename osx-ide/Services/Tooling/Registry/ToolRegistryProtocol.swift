import Foundation
protocol ToolRegistryProtocol: Sendable { func register(_: ToolDefinition); func tool(named: String)->ToolDefinition?; func tools(for: AgentMode)->[ToolDefinition]; var allTools:[ToolDefinition]{get} }
