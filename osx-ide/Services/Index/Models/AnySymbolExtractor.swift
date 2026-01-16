import Foundation

public struct AnySymbolExtractor: Sendable {
    private let _extract: @Sendable (_ content: String, _ resourceId: String) -> [Symbol]

    public init(_ extract: @Sendable @escaping (_ content: String, _ resourceId: String) -> [Symbol]) {
        self._extract = extract
    }

    public func extractSymbols(content: String, resourceId: String) -> [Symbol] {
        _extract(content, resourceId)
    }
}
