import Foundation

public final class WhereSymbolTool: AITool {
    public let name = "where_symbol"
    public let description = "Find where a symbol is located in the project. Pass the symbol ID from locate_symbol."
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

    private let databaseProvider: () -> DatabaseStore?

    public init(databaseProvider: @escaping () -> DatabaseStore?) {
        self.databaseProvider = databaseProvider
    }

    public func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let id = raw["id"] as? Int else {
            return "Missing or invalid 'id' argument. Use locate_symbol first to get the ID."
        }
        guard let db = databaseProvider() else {
            return "Symbol index not available."
        }
        let locations = try await db.whereSymbol(id: id)
        guard !locations.isEmpty else {
            return "No locations found for symbol id \(id)."
        }
        return locations.map { loc in
            "\(loc.filePath):\(loc.lineStart)-\(loc.lineEnd)"
        }.joined(separator: "\n")
    }
}
