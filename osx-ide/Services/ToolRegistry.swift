import Foundation

final class ToolRegistry: Sendable {
    static let shared = ToolRegistry()

    private let tools: [String: AITool]

    init(tools: [AITool] = []) {
        var toolMap: [String: AITool] = [:]
        for tool in tools {
            toolMap[tool.name] = tool
        }
        self.tools = toolMap
    }

    func getTool(named name: String) -> AITool? {
        return tools[name]
    }

    func availableTools() -> [AITool] {
        return Array(tools.values)
    }

    func toolDefinitions() -> [[String: Any]] {
        return tools.values.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.parameters
                ]
            ]
        }
    }
}
