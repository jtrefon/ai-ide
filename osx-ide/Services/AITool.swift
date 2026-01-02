//
//  AITool.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

/// Defines a tool that can be used by the AI agent
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get } // JSON Schema
    
    func execute(arguments: [String: Any]) async throws -> String
}

/// Registry to manage available AI tools
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
    
    /// Returns the tool definitions in a format compatible with AI models (OpenRouter/OpenAI)
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

/// Represents a tool call requested by the AI
public struct AIToolCall: Codable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let arguments: [String: Any]
    
    public enum CodingKeys: String, CodingKey {
        case id
        case function
    }
    
    public enum FunctionCodingKeys: String, CodingKey {
        case name
        case arguments
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        
        let functionContainer = try container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        name = try functionContainer.decode(String.self, forKey: .name)
        
        let argumentsString = try functionContainer.decode(String.self, forKey: .arguments)
        if let data = argumentsString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = dict
        } else {
            arguments = [:]
        }
    }
    
    // Manual initializer for convenience or tests
    init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        
        var functionContainer = container.nestedContainer(keyedBy: FunctionCodingKeys.self, forKey: .function)
        try functionContainer.encode(name, forKey: .name)
        
        // Encode arguments as JSON string to match init(from:)
        let jsonData = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        try functionContainer.encode(jsonString, forKey: .arguments)
    }
}
