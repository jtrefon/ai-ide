import AppKit

/// Represents semantic roles for syntax highlighting.
/// This allows different languages to map their specific tokens to a common set of roles.
public enum HighlightRole: String, CaseIterable, Sendable {
    case key
    case string
    case number
    case boolean
    case null
    case keyword
    case type
    case comment
    case attribute
    case tag
    case selector
    case property
    case function
    case brace
    case bracket
    case comma
    case colon
    case quote
    case unknown
}

/// A semantic palette mapping highlight roles to specific colors.
public struct HighlightPalette: Sendable {
    private var colors: [HighlightRole: NSColor]

    public init(colors: [HighlightRole: NSColor] = [:]) {
        self.colors = colors
    }

    public func color(for role: HighlightRole) -> NSColor? {
        return colors[role]
    }

    public mutating func setColor(_ color: NSColor, for role: HighlightRole) {
        colors[role] = color
    }
}

/// Interface for anything that can provide a semantic highlight palette.
public protocol HighlightPaletteProviding {
    var highlightPalette: HighlightPalette { get }
}
