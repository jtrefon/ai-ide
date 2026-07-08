import Foundation

struct ToolCallFallbackParser: Sendable {
    private let decoders: [ToolCallDecoder]

    init(decoders: [ToolCallDecoder] = ToolCallFallbackParser.defaultDecoders) {
        self.decoders = decoders
    }

    static let defaultDecoders: [ToolCallDecoder] = [
        StructuredXMLDecoder(),
        LegacyToolCodeDecoder(),
        BareFunctionDecoder(),
        ToolCallBlockDecoder(),
        MinimaxDecoder(),
        GemmaFormatDecoder(),
        JSONToolCallDecoder()
    ]

    func decodeAll(from content: String) -> [AIToolCall]? {
        for decoder in decoders {
            if let calls = decoder.decode(from: content), !calls.isEmpty {
                return calls
            }
        }
        return nil
    }

    static func stripMarkup(from content: String) -> String {
        var output = content
        for pattern in Self.stripPatterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let stripPatterns = [
        #"(?is)<tool_call>\s*.*?\s*</tool_call>"#,
        #"(?is)<tool_code>\s*.*?\s*</tool_code>"#,
        #"(?is)<minimax:tool_call>\s*.*?\s*</minimax:tool_call>"#,
        #"(?is)<invoke\s+name=\"[^\"]+\"\s*>.*?</invoke>"#,
        #"(?is)<tool\s+name=\"[^\"]+\"\s*>.*?</tool>"#,
        #"(?is)</?arg\s+name=\"[^\"]+\">"#,
        #"(?is)</?parameter\s+name=\"[^\"]+\">"#,
        #"(?is)</?param\s+name=\"[^\"]+\">"#,
        #"(?is)<function=[^\s>]+>\s*|</function>"#,
        #"(?is)<parameter=[^\s>]+>\s*|</parameter>"#
    ]
}

protocol ToolCallDecoder: Sendable {
    func decode(from content: String) -> [AIToolCall]?
}

enum ParserHelper {
    static func normalizeName(_ rawName: String) -> String {
        let decoded = Self.decodeHTMLEntities(rawName).trimmingCharacters(in: .whitespacesAndNewlines)
        return ToolAliasRegistry.shared.canonicalName(for: decoded)
    }

    static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func recoverArguments(in body: String, range: NSRange, regex: NSRegularExpression) -> [String: Any] {
        let parameters = regex.matches(in: body, options: [], range: range)
        var arguments: [String: Any] = [:]
        for parameter in parameters {
            guard parameter.numberOfRanges == 3,
                  let nameRange = Range(parameter.range(at: 1), in: body),
                  let valueRange = Range(parameter.range(at: 2), in: body) else { continue }
            let name = decodeHTMLEntities(String(body[nameRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let value = decodeHTMLEntities(String(body[valueRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            arguments[name] = value
        }
        return arguments
    }
}

// MARK: - Structured XML: <tool_call><tool name="..."><arg name="...">value</arg></tool></tool_call>

struct StructuredXMLDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let pattern = #"<tool_call>\s*(.*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let toolPattern = #"<tool\s+name=\"([^\"]+)\"\s*>(.*?)</tool>"#
        let functionEqPattern = #"<function=([^\s>]+)>\s*(.*?)\s*</function>"#
        let argPattern = #"<arg\s+name=\"([^\"]+)\"\s*>(.*?)</arg>"#
        let parameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        let parameterEqPattern = #"<parameter=([^\s>]+)>\s*(.*?)\s*</parameter>"#
        guard let toolRegex = try? NSRegularExpression(pattern: toolPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let functionEqRegex = try? NSRegularExpression(pattern: functionEqPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let argRegex = try? NSRegularExpression(pattern: argPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let parameterRegex = try? NSRegularExpression(pattern: parameterPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let parameterEqRegex = try? NSRegularExpression(pattern: parameterEqPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }

        let toolCalls = matches.flatMap { match -> [AIToolCall] in
            guard match.numberOfRanges == 2, let bodyRange = Range(match.range(at: 1), in: content) else { return [] }
            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let standardMatches = toolRegex.matches(in: body, options: [], range: bodyNSRange)
            let functionEqMatches = standardMatches.isEmpty ? functionEqRegex.matches(in: body, options: [], range: bodyNSRange) : []
            let matched = standardMatches.isEmpty ? functionEqMatches : standardMatches

            return matched.compactMap { toolMatch in
                guard toolMatch.numberOfRanges == 3,
                      let nameRange = Range(toolMatch.range(at: 1), in: body),
                      let toolBodyRange = Range(toolMatch.range(at: 2), in: body) else { return nil }
                let toolName = ParserHelper.normalizeName(String(body[nameRange]))
                guard !toolName.isEmpty else { return nil }
                let toolBody = String(body[toolBodyRange])
                let toolBodyNSRange = NSRange(toolBody.startIndex..<toolBody.endIndex, in: toolBody)
                var arguments = ParserHelper.recoverArguments(in: toolBody, range: toolBodyNSRange, regex: argRegex)
                if arguments.isEmpty {
                    arguments = ParserHelper.recoverArguments(in: toolBody, range: toolBodyNSRange, regex: parameterRegex)
                }
                if arguments.isEmpty, !functionEqMatches.isEmpty {
                    arguments = ParserHelper.recoverArguments(in: toolBody, range: toolBodyNSRange, regex: parameterEqRegex)
                }
                return AIToolCall(id: UUID().uuidString, name: toolName, arguments: arguments)
            }
        }
        return toolCalls.isEmpty ? nil : toolCalls
    }
}

// MARK: - Legacy Tool Code: <tool_code>tool_name<param name="...">value</param></tool_code>

struct LegacyToolCodeDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let pattern = #"<tool_code>\s*(.*?)\s*</tool_code>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let paramPattern = #"<param\s+name=\"([^\"]+)\"\s*>(.*?)</param>"#
        let selfClosingToolPattern = #"<tool\s+name=\"([^\"]+)\"(.*?)/>"#
        let inlineAttributePattern = #"([a-zA-Z_][a-zA-Z0-9_\-]*)=\"(.*?)\""#
        guard let paramRegex = try? NSRegularExpression(pattern: paramPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let selfClosingToolRegex = try? NSRegularExpression(pattern: selfClosingToolPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let inlineAttributeRegex = try? NSRegularExpression(pattern: inlineAttributePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }

        let toolCalls = matches.flatMap { match -> [AIToolCall] in
            guard match.numberOfRanges == 2, let bodyRange = Range(match.range(at: 1), in: content) else { return [] }
            let body = String(content[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)

            let inlineTools = selfClosingToolRegex.matches(in: body, options: [], range: bodyNSRange).compactMap { toolMatch -> AIToolCall? in
                guard toolMatch.numberOfRanges == 3,
                      let nameRange = Range(toolMatch.range(at: 1), in: body),
                      let attributesRange = Range(toolMatch.range(at: 2), in: body) else { return nil }
                let toolName = ParserHelper.normalizeName(String(body[nameRange]))
                guard !toolName.isEmpty else { return nil }
                let attributesText = String(body[attributesRange])
                let attributesNSRange = NSRange(attributesText.startIndex..<attributesText.endIndex, in: attributesText)
                var arguments: [String: Any] = [:]
                for attributeMatch in inlineAttributeRegex.matches(in: attributesText, options: [], range: attributesNSRange) {
                    guard attributeMatch.numberOfRanges == 3,
                          let keyRange = Range(attributeMatch.range(at: 1), in: attributesText),
                          let valueRange = Range(attributeMatch.range(at: 2), in: attributesText) else { continue }
                    let key = ParserHelper.decodeHTMLEntities(String(attributesText[keyRange])).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard key != "name", !key.isEmpty else { continue }
                    let value = ParserHelper.decodeHTMLEntities(String(attributesText[valueRange])).trimmingCharacters(in: .whitespacesAndNewlines)
                    arguments[key] = value
                }
                return AIToolCall(id: UUID().uuidString, name: toolName, arguments: arguments)
            }
            if !inlineTools.isEmpty { return inlineTools }

            let lines = body.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard let firstLine = lines.first else { return [] }
            let toolName = ParserHelper.normalizeName(firstLine)
            guard !toolName.isEmpty else { return [] }
            let arguments = ParserHelper.recoverArguments(in: body, range: bodyNSRange, regex: paramRegex)
            return [AIToolCall(id: UUID().uuidString, name: toolName, arguments: arguments)]
        }
        return toolCalls.isEmpty ? nil : toolCalls
    }
}

// MARK: - Bare Function: <function=name><parameter=key>value</parameter></function>

struct BareFunctionDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let pattern = #"<function=([^\s>]+)>\s*(.*?)\s*</function>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let parameterPattern = #"<parameter=([^\s>]+)>\s*(.*?)\s*</parameter>"#
        let namedParameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        guard let paramRegex = try? NSRegularExpression(pattern: parameterPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let namedParamRegex = try? NSRegularExpression(pattern: namedParameterPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }

        let toolCalls = matches.compactMap { match -> AIToolCall? in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: content),
                  let bodyRange = Range(match.range(at: 2), in: content) else { return nil }
            let toolName = ParserHelper.normalizeName(String(content[nameRange]))
            guard !toolName.isEmpty else { return nil }
            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)
            var arguments = ParserHelper.recoverArguments(in: body, range: bodyNSRange, regex: paramRegex)
            if arguments.isEmpty {
                arguments = ParserHelper.recoverArguments(in: body, range: bodyNSRange, regex: namedParamRegex)
            }
            return AIToolCall(id: UUID().uuidString, name: toolName, arguments: arguments)
        }
        return toolCalls.isEmpty ? nil : toolCalls
    }
}

// MARK: - Tool Call Block: <tool_call>/path\ncontent</tool_call> → write_file

struct ToolCallBlockDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let parts = content.components(separatedBy: "<tool_call>")
        guard parts.count > 1 else { return nil }
        var toolCalls: [AIToolCall] = []
        for part in parts.dropFirst() {
            let body: String
            if let closeRange = part.range(of: "</tool_call>", options: .caseInsensitive) {
                body = String(part[..<closeRange.lowerBound])
            } else {
                body = part
            }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lines = trimmed.components(separatedBy: "\n")
            guard lines.count >= 2 else { continue }
            let path = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.hasPrefix("/") || path.hasPrefix(".") else { continue }
            let fileContent = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileContent.isEmpty else { continue }
            toolCalls.append(AIToolCall(
                id: UUID().uuidString,
                name: "write_file",
                arguments: ["path": path, "content": fileContent]
            ))
        }
        return toolCalls.isEmpty ? nil : toolCalls
    }
}

// MARK: - Minimax: <invoke name="..."><parameter name="...">value</parameter></invoke>

struct MinimaxDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let pattern = #"<invoke\s+name=\"([^\"]+)\"\s*>(.*?)</invoke>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let contentRange = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, options: [], range: contentRange)
        guard !matches.isEmpty else { return nil }

        let parameterPattern = #"<parameter\s+name=\"([^\"]+)\"\s*>(.*?)</parameter>"#
        guard let parameterRegex = try? NSRegularExpression(pattern: parameterPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }

        let toolCalls = matches.compactMap { match -> AIToolCall? in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: content),
                  let bodyRange = Range(match.range(at: 2), in: content) else { return nil }
            let toolName = ParserHelper.normalizeName(String(content[nameRange]))
            guard !toolName.isEmpty else { return nil }
            let body = String(content[bodyRange])
            let bodyNSRange = NSRange(body.startIndex..<body.endIndex, in: body)
            let arguments = ParserHelper.recoverArguments(in: body, range: bodyNSRange, regex: parameterRegex)
            return AIToolCall(id: UUID().uuidString, name: toolName, arguments: arguments)
        }
        return toolCalls.isEmpty ? nil : toolCalls
    }
}

// MARK: - Gemma 4: call:name{json_args}

struct GemmaFormatDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        let calls = parseGemmaCalls(from: content)
        return calls.isEmpty ? nil : calls
    }

    private func parseGemmaCalls(from content: String) -> [AIToolCall] {
        let marker = "call:"
        var results: [AIToolCall] = []
        var searchStart = content.startIndex

        while let markerRange = content.range(of: marker, range: searchStart..<content.endIndex) {
            let afterMarker = markerRange.upperBound
            var nameEnd = afterMarker
            while nameEnd < content.endIndex, content[nameEnd].isLetter || content[nameEnd].isNumber || content[nameEnd] == "_" {
                nameEnd = content.index(after: nameEnd)
            }
            guard nameEnd > afterMarker else {
                searchStart = markerRange.upperBound
                continue
            }
            let name = String(content[afterMarker..<nameEnd])
            var braceStart = nameEnd
            while braceStart < content.endIndex, content[braceStart].isWhitespace {
                braceStart = content.index(after: braceStart)
            }
            guard braceStart < content.endIndex, content[braceStart] == "{" else {
                searchStart = nameEnd
                continue
            }
            var depth = 1
            var pos = content.index(after: braceStart)
            while pos < content.endIndex && depth > 0 {
                let ch = content[pos]
                if ch == "{" { depth += 1 }
                else if ch == "}" { depth -= 1 }
                if depth > 0 { pos = content.index(after: pos) }
            }
            guard depth == 0 else {
                searchStart = nameEnd
                continue
            }
            let argsText = String(content[content.index(after: braceStart)..<pos])
            let cleanedArgs = argsText.replacingOccurrences(of: "<|\"|>", with: "\"")
            let jsonText = "{\(cleanedArgs)}"
            var arguments: [String: Any] = [:]
            if let jsonData = jsonText.data(using: .utf8),
               let jsonObj = try? JSONSerialization.jsonObject(with: jsonData),
               let argsDict = jsonObj as? [String: Any] {
                arguments = argsDict
            } else {
                var fallbackArgs: [String: String] = [:]
                let stripped = cleanedArgs.replacingOccurrences(of: "\"", with: "")
                let pairPattern = #"(\w+):(.*?)(?:,\s*\w+|$)"#
                if let pairRegex = try? NSRegularExpression(pattern: pairPattern, options: [.dotMatchesLineSeparators]) {
                    let pairRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
                    let pairMatches = pairRegex.matches(in: stripped, options: [], range: pairRange)
                    for pair in pairMatches {
                        guard pair.numberOfRanges >= 3,
                              let keyRange = Range(pair.range(at: 1), in: stripped),
                              let valRange = Range(pair.range(at: 2), in: stripped) else { continue }
                        let key = String(stripped[keyRange])
                        let val = String(stripped[valRange]).trimmingCharacters(in: .whitespaces)
                        fallbackArgs[key] = val
                    }
                }
                arguments = fallbackArgs
            }
            results.append(AIToolCall(id: UUID().uuidString, name: name, arguments: arguments))
            searchStart = content.index(after: pos)
        }
        return results
    }
}

// MARK: - JSON Tool Call

struct JSONToolCallDecoder: ToolCallDecoder {
    func decode(from content: String) -> [AIToolCall]? {
        if let single = decodeSingle(from: content) {
            return [single]
        }
        if let envelope = decodeEnvelope(from: content), !envelope.isEmpty {
            return envelope
        }
        if let fenced = extractFirstJSONCodeBlock(from: content) {
            if let single = decodeSingle(from: fenced) {
                return [single]
            }
            if let envelope = decodeEnvelope(from: fenced), !envelope.isEmpty {
                return envelope
            }
        }
        return nil
    }

    private func decodeSingle(from raw: String) -> AIToolCall? {
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIToolCall.self, from: data) else { return nil }
        return decoded
    }

    private func decodeEnvelope(from raw: String) -> [AIToolCall]? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawToolCalls = object["tool_calls"] as? [[String: Any]] else { return nil }
        let decoded = rawToolCalls.compactMap { rawCall -> AIToolCall? in
            guard JSONSerialization.isValidJSONObject(rawCall),
                  let callData = try? JSONSerialization.data(withJSONObject: rawCall),
                  let call = try? JSONDecoder().decode(AIToolCall.self, from: callData) else { return nil }
            return call
        }
        return decoded.isEmpty ? nil : decoded
    }

    private func extractFirstJSONCodeBlock(from content: String) -> String? {
        guard let openingRange = content.range(of: "```json") ?? content.range(of: "```") else { return nil }
        let remainder = content[openingRange.upperBound...]
        guard let closingRange = remainder.range(of: "```") else { return nil }
        return remainder[..<closingRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Gemma Format Parser (standalone for top-level use)

extension ToolCallFallbackParser {
    static func decodeGemmaToolCalls(from content: String) -> [AIToolCall]? {
        GemmaFormatDecoder().decode(from: content)
    }

    static func decodeAllFallback(from content: String) -> [AIToolCall]? {
        ToolCallFallbackParser().decodeAll(from: content)
    }
}
