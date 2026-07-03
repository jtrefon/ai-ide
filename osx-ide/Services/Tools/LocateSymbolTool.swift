import Foundation

public final class LocateSymbolTool: AITool {
    public let name = "locate_symbol"
    public let description = "Look up a symbol by exact name. Returns its internal ID. " +
        "Use before inspect_symbol or where_symbol."
    public var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "Exact symbol name to locate (case-sensitive)"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["name"]
        ]
    }

    private let databaseProvider: @Sendable () -> DatabaseStore?

    public init(databaseProvider: @escaping @Sendable () -> DatabaseStore?) {
        self.databaseProvider = databaseProvider
    }

    public func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return "Missing 'name' argument."
        }
        guard let database = databaseProvider() else {
            return "Symbol index not available."
        }
        guard let id = try await database.locateSymbolId(name: name) else {
            return "Symbol '\(name)' not found."
        }
        return "Found: id=\(id), name='\(name)'. Use inspect_symbol(id: \(id)) " +
            "or where_symbol(id: \(id)) for location."
    }
}
