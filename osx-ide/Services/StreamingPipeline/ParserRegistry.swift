import Foundation

/// Dynamically extensible registry of tool-call format parsers (Strategy pattern).
///
/// OCP: Add new model formats by creating a new `ToolCallFormatParser` and
/// registering it. No existing code changes needed.
public final class ParserRegistry: @unchecked Sendable {
    private var parsers: [String: ToolCallFormatParser] = [:]

    public init() {}

    /// Register a parser for a specific format.
    public func register(_ parser: ToolCallFormatParser) {
        parsers[parser.formatIdentifier] = parser
    }

    /// Retrieve a parser by its format identifier.
    public func parser(for identifier: String) -> ToolCallFormatParser? {
        parsers[identifier]
    }

    /// All currently registered parsers.
    public func allParsers() -> [ToolCallFormatParser] {
        Array(parsers.values)
    }

    /// Remove a parser.
    public func unregister(_ parser: ToolCallFormatParser) {
        parsers.removeValue(forKey: parser.formatIdentifier)
    }

    /// Remove all parsers.
    public func clear() {
        parsers.removeAll()
    }
}

// MARK: - Default registry with all known parsers

extension ParserRegistry {
    /// Creates a registry pre-populated with all known parsers.
    public static func `default`() -> ParserRegistry {
        let r = ParserRegistry()
        r.register(JSONToolCallFormatParser())
        r.register(XMLToolCallFormatParser())
        r.register(LegacyToolCodeFormatParser())
        r.register(BareFunctionFormatParser())
        r.register(ToolCallBlockFormatParser())
        r.register(MinimaxFormatParser())
        r.register(GemmaFormatParser())
        return r
    }
}
