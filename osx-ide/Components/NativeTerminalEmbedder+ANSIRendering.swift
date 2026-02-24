import AppKit
import Foundation

extension NativeTerminalEmbedder {
    /// Convert ANSI color code (0-7) to NSColor
    func ansiColor(_ code: Int) -> NSColor {
        let colors: [NSColor] = [
            .black,
            .red,
            .green,
            .yellow,
            .blue,
            .magenta,
            .cyan,
            .white
        ]
        return (0..<colors.count).contains(code) ? colors[code] : .green
    }

    /// Convert ANSI bright color code (0-7) to NSColor
    func ansiBrightColor(_ code: Int) -> NSColor {
        let brightColors: [NSColor] = [
            NSColor(white: 0.3, alpha: 1.0),   // Bright Black (Dark Gray)
            NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0),  // Bright Red
            NSColor(red: 0.3, green: 1.0, blue: 0.3, alpha: 1.0),  // Bright Green
            NSColor(red: 1.0, green: 1.0, blue: 0.3, alpha: 1.0),  // Bright Yellow
            NSColor(red: 0.3, green: 0.3, blue: 1.0, alpha: 1.0),  // Bright Blue
            NSColor(red: 1.0, green: 0.3, blue: 1.0, alpha: 1.0),  // Bright Magenta
            NSColor(red: 0.3, green: 1.0, blue: 1.0, alpha: 1.0),  // Bright Cyan
            NSColor.white  // Bright White
        ]
        return (0..<brightColors.count).contains(code) ? brightColors[code] : NSColor.green
    }
}
