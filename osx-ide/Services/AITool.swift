//
//  AITool.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation

public struct ToolArguments: @unchecked Sendable {
    public let raw: [String: Any]

    public init(_ raw: [String: Any]) {
        self.raw = raw
    }
}

/// Defines a tool that can be used by the AI agent
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get } // JSON Schema

    func execute(arguments: ToolArguments) async throws -> String
}
