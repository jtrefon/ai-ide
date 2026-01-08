import AppKit

public struct HighlightDiagnosticsSwatch: @unchecked Sendable {
    public let name: String
    public let color: NSColor

    public init(name: String, color: NSColor) {
        self.name = name
        self.color = color
    }
}

public protocol HighlightDiagnosticsPaletteProviding {
    var highlightDiagnosticsPalette: [HighlightDiagnosticsSwatch] { get }
}
