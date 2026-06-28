// Copyright © 2025 Apple Inc.

import Foundation

/// Parser for Gemma 4 tool call format: call:name{key:<|"|>value<|"|>,num:42}
/// Uses <|"|> as string delimiters instead of standard JSON quotes.
/// Reference: https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/tool_parsers/gemma4.py
public struct GemmaFunctionParser: ToolCallParser, Sendable {
    public let startTag: String? = "<|tool_call>"
    public let endTag: String? = "<tool_call|>"

    private let escapeMarker = "<|\"|>"

    public init() {}

    public func parse(content: String, tools: [[String: any Sendable]]?) -> ToolCall? {
        // Strip tags if present
        var text = content
        if let start = startTag {
            text = text.replacingOccurrences(of: start, with: "")
        }
        if let end = endTag {
            text = text.replacingOccurrences(of: end, with: "")
        }

        // Find "call:" followed by function name and arguments in braces
        guard let callRange = text.range(of: "call:") else { return nil }

        let remaining = String(text[callRange.upperBound...])

        // Extract function name (word characters until {)
        guard let braceStart = remaining.firstIndex(of: "{") else { return nil }
        let funcName = String(remaining[..<braceStart]).trimmingCharacters(in: .whitespaces)

        guard !funcName.isEmpty else { return nil }

        // Extract arguments string — use brace matching to find the closing brace
        // so that nested objects in values don't confuse the parser
        var depth = 0
        var braceEnd: String.Index?
        var idx = braceStart
        while idx < remaining.endIndex {
            let ch = remaining[idx]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    braceEnd = idx
                    break
                }
            }
            idx = remaining.index(after: idx)
        }

        guard let braceEnd else { return nil }
        let argsStr = String(remaining[remaining.index(after: braceStart) ..< braceEnd])

        // Convert Gemma 4 args to valid JSON, then parse
        let jsonString = gemma4ArgsToJSON(argsStr)
        guard let data = jsonString.data(using: .utf8),
              let parsed = deserializeJSON(data) as? [String: any Sendable]
        else {
            // Fallback: if JSON conversion fails, try the old-style key:value parsing
            return fallbackParse(funcName: funcName, argsStr: argsStr)
        }

        return ToolCall(function: .init(name: funcName, arguments: parsed))
    }

    /// Convert Gemma 4 argument format to valid JSON.
    /// Gemma 4 uses unquoted keys and <|"|> as string delimiters.
    private func gemma4ArgsToJSON(_ text: String) -> String {
        // Step 1: Extract all <|"|>...<|"|> strings and replace with placeholders
        var strings: [String] = []
        var working = text
        while let startRange = working.range(of: escapeMarker) {
            guard let endRange = working.range(of: escapeMarker, range: working.index(startRange.upperBound, offsetBy: 0)..<working.endIndex) else { break }
            let stringValue = String(working[startRange.upperBound ..< endRange.lowerBound])
            strings.append(stringValue)
            let placeholder = "\"__STR_\(strings.count - 1)__\""
            working.replaceSubrange(startRange.lowerBound ..< endRange.upperBound, with: placeholder)
        }

        // Step 2: Quote bare keys (word characters followed by colon)
        // Match patterns like `key:` or `key:` at the start or after `{` or `,`
        working = quoteBareKeys(in: working)

        // Step 3: Restore string placeholders with properly escaped JSON strings
        for (i, str) in strings.enumerated() {
            let placeholder = "\"__STR_\(i)__\""
            let escaped = str
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            working = working.replacingOccurrences(of: placeholder, with: "\"\(escaped)\"")
        }

        return "{\(working)}"
    }

    /// Quote bare keys in the argument string for JSON compliance.
    /// Transforms `key:value` into `"key":value` and `key:{` into `"key":{`.
    private func quoteBareKeys(in text: String) -> String {
        var result = text
        // Pattern: at start, or after { or ,, followed by word chars, then :
        let pattern = #"(^|[{,]\s*)([A-Za-z_][A-Za-z0-9_]*\s*):"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return result
        }
        let nsString = NSString(string: result)
        let range = NSRange(location: 0, length: nsString.length)
        // Collect matches in reverse order to preserve indices
        let matches = regex.matches(in: result, options: [], range: range).reversed()
        for match in matches {
            guard let matchRange = Range(match.range, in: result),
                  let keyRange = Range(match.range(at: 2), in: result) else { continue }
            let prefix = nsString.substring(with: match.range(at: 1))
            let key = String(result[keyRange]).trimmingCharacters(in: .whitespaces)
            let replacement = "\(prefix)\"\(key)\":"
            result.replaceSubrange(matchRange, with: replacement)
        }
        return result
    }

    /// Fallback parser using the old comma-split approach for edge cases
    /// where the JSON conversion fails.
    private func fallbackParse(funcName: String, argsStr: String) -> ToolCall? {
        var arguments: [String: any Sendable] = [:]
        var remaining = argsStr

        while !remaining.isEmpty {
            guard let colonIdx = remaining.firstIndex(of: ":") else { break }
            let key = String(remaining[..<colonIdx])
            remaining = String(remaining[remaining.index(after: colonIdx)...])

            if remaining.hasPrefix(escapeMarker) {
                remaining = String(remaining.dropFirst(escapeMarker.count))
                guard let endEscape = remaining.range(of: escapeMarker) else { break }
                let value = String(remaining[..<endEscape.lowerBound])
                arguments[key] = value
                remaining = String(remaining[endEscape.upperBound...])
                if remaining.hasPrefix(",") {
                    remaining = String(remaining.dropFirst())
                }
                continue
            }

            let commaIdx = remaining.firstIndex(of: ",") ?? remaining.endIndex
            let value = String(remaining[..<commaIdx])
            remaining = commaIdx < remaining.endIndex
                ? String(remaining[remaining.index(after: commaIdx)...]) : ""

            if let data = value.data(using: .utf8),
                let json = deserializeJSON(data) {
                arguments[key] = json
            } else {
                arguments[key] = value
            }
        }

        return ToolCall(function: .init(name: funcName, arguments: arguments))
    }
}
