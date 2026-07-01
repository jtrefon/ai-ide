import Foundation

/// Strips ANSI escape codes from terminal output.
/// run_command output often contains color codes like `[33mclass[39m=[32m"todo-app"[39m`
/// which confuse the model when fed back as tool results.
struct ANSIStripper: Sendable {
    /// Strip all ANSI escape sequences from a string.
    /// Handles SGR codes (`\e[<digits>m`), cursor movement, screen clears, etc.
    static func strip(_ text: String) -> String {
        // Pattern matches: ESC[<anything ending with a letter>
        // This covers SGR (m), cursor movement (A/B/C/D/H/J), screen clear (2J), etc.
        let pattern = #"\e\[[0-9;]*[a-zA-Z]"#
        let stripped = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)

        // Also strip bare ESC characters not followed by [
        let bareEsc = stripped.replacingOccurrences(of: "\u{1b}", with: "")

        // Strip OSC sequences: ESC]<anything>ESC\
        let oscPattern = #"\e\].*?\e\\"#
        let final = bareEsc.replacingOccurrences(of: oscPattern, with: "", options: .regularExpression)

        return final
    }

    /// Strip ANSI codes and truncate to maxChars for model consumption.
    static func stripAndTruncate(_ text: String, maxChars: Int = 20000) -> String {
        let stripped = strip(text)
        if stripped.count <= maxChars { return stripped }
        return String(stripped.prefix(maxChars)) +
            "\n\n... [output truncated at \(maxChars) characters]"
    }
}
