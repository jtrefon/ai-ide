import Foundation

public final class InspectSymbolTool: AITool {
    public let name = "inspect_symbol"
    public let description = "Get details about a symbol by its ID (from locate_symbol). " +
        "Returns kind, scope, signature, and parent."
    public var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "id": [
                    "type": "integer",
                    "description": "Symbol ID from locate_symbol"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["id"]
        ]
    }

    private let databaseProvider: @Sendable () -> DatabaseStore?

    public init(databaseProvider: @escaping @Sendable () -> DatabaseStore?) {
        self.databaseProvider = databaseProvider
    }

    public func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let id = raw["id"] as? Int else {
            return "Missing or invalid 'id' argument. Use locate_symbol first to get the ID."
        }
        guard let database = databaseProvider() else {
            return "Symbol index not available."
        }
        guard let details = try await database.inspectSymbol(id: id) else {
            return "No details found for symbol id \(id)."
        }
        var lines: [String] = ["Symbol \(id):"]
        lines.append("  kind: \(details.kind)")
        if !details.scope.isEmpty { lines.append("  scope: \(details.scope)") }
        if !details.signature.isEmpty { lines.append("  signature: \(details.signature)") }
        if !details.parentName.isEmpty { lines.append("  parent: \(details.parentName)") }
        return lines.joined(separator: "\n")
    }
}
