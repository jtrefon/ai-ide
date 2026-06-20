//
//  ChatPromptBuilder.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation

/// Responsible for constructing and formatting prompts for the AI service.
class ChatPromptBuilder {
    enum DeliveryStatus {
        case done
        case needsWork
    }

    /// Structured representation of a model response split into reasoning, content, and tool calls.
    struct ParsedModelResponse: Sendable {
        let reasoning: String?
        let content: String?
        let toolCalls: [AIToolCall]

        static func empty() -> ParsedModelResponse {
            ParsedModelResponse(reasoning: nil, content: nil, toolCalls: [])
        }
    }

    /// Parses raw model output into structured components.
    /// Handles Gemma 4 format: [<|channel>thought\n...<channel|>][content][<|tool_call>call:name{json}<tool_call|>][<turn|>]
    static func parseModelResponse(_ text: String) -> ParsedModelResponse {
        guard !text.isEmpty else { return .empty() }

        // 1. Extract reasoning from <|channel>thought\n...<channel|>
        let afterReasoning: String
        let reasoning: String?
        if let open = text.range(of: "<|channel>thought", options: [.caseInsensitive]),
           let close = text[open.upperBound...].range(of: "<channel|>")
        {
            let reasoningText = String(text[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            reasoning = reasoningText.isEmpty ? nil : reasoningText
            afterReasoning = String(text[close.upperBound...])
        } else {
            reasoning = nil
            afterReasoning = text
        }

        // 2. Extract tool calls from remaining text
        var content = afterReasoning
        var toolCalls: [AIToolCall] = []
        let toolCallPattern = #"(?is)<\|tool_call>(.*?)<tool_call\|>"#
        if let toolRegex = try? NSRegularExpression(pattern: toolCallPattern) {
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            let matches = toolRegex.matches(in: content, range: range)
            if !matches.isEmpty {
                for match in matches where match.numberOfRanges >= 2 {
                    if let callRange = Range(match.range(at: 1), in: content) {
                        let callBody = String(content[callRange])
                        if let parsed = Self.parseGemmaToolCall(from: callBody) {
                            toolCalls.append(parsed)
                        }
                    }
                }
                // Remove tool call blocks from content
                content = toolRegex.stringByReplacingMatches(in: content, range: range, withTemplate: "")
            }
        }

        // 3. Remove turn markers and remaining tags from content
        content = stripTextualToolCallMarkup(from: content)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedModelResponse(
            reasoning: reasoning,
            content: content.isEmpty ? nil : content,
            toolCalls: toolCalls
        )
    }

    private static func parseGemmaToolCall(from body: String) -> AIToolCall? {
        // Format: call:name{json_args}
        let pattern = #"call:(\w+)\{((?:[^{}]|\{[^{}]*\})*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..<body.endIndex, in: body)),
              match.numberOfRanges >= 3,
              let nameRange = Range(match.range(at: 1), in: body),
              let argsRange = Range(match.range(at: 2), in: body) else {
            return nil
        }
        let name = String(body[nameRange])
        var argsText = String(body[argsRange])

        // Gemma 4 uses <|"|> (token id 52) as a string delimiter.
        // Replace with " so the text becomes valid JSON.
        argsText = argsText.replacingOccurrences(of: "<|\"|>", with: "\"")

        // Try proper JSON parsing first
        let jsonText = "{\(argsText)}"
        if let jsonData = jsonText.data(using: .utf8),
           let jsonObj = try? JSONSerialization.jsonObject(with: jsonData),
           let argsDict = jsonObj as? [String: Any] {
            return AIToolCall(id: UUID().uuidString, name: name, arguments: argsDict)
        }

        // Fallback: strip quotes and parse bare key:value pairs
        var args: [String: String] = [:]
        let stripped = argsText
            .replacingOccurrences(of: "\"", with: "")
        let pairPattern = #"(\w+):(.*?)(?:,\s*\w+|$)"#
        if let pairRegex = try? NSRegularExpression(pattern: pairPattern, options: [.dotMatchesLineSeparators]) {
            let pairRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
            let pairMatches = pairRegex.matches(in: stripped, range: pairRange)
            for pair in pairMatches where pair.numberOfRanges >= 3 {
                if let keyRange = Range(pair.range(at: 1), in: stripped),
                   let valRange = Range(pair.range(at: 2), in: stripped) {
                    let key = String(stripped[keyRange])
                    let val = String(stripped[valRange]).trimmingCharacters(in: .whitespaces)
                    args[key] = val
                }
            }
        }
        return AIToolCall(id: UUID().uuidString, name: name, arguments: args)
    }


    /// Splits reasoning from the raw AI response text.
    /// - Parameter text: The raw response text.
    /// - Returns: A tuple containing the reasoning string (if found) and the cleaned content.
    static func splitReasoning(from text: String) -> (reasoning: String?, content: String) {
        guard !text.isEmpty else { return (nil, "") }

        if let tagged = splitTaggedReasoning(from: text) {
            return tagged
        }

        if let plain = splitPlainReasoning(from: text) {
            return plain
        }

        return (nil, text)
    }

    /// Sanitizes model text for user-visible rendering:
    /// strips reasoning from rendered content while preserving paragraph breaks.
    static func contentForDisplay(from text: String) -> String {
        let split = splitReasoning(from: text)
        let withoutToolMarkup = stripTextualToolCallMarkup(from: split.content)
        return normalizeDisplayWhitespace(withoutToolMarkup)
    }

    static func reasoningForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let sectionLabels = [
            "Codebase Review & Insights",
            "Architecture:",
            "UI Layer:",
            "Routing:",
            "Strengths:",
            "Potential Issues:",
            "Recommendations:",
            "Remaining Work:",
            "Status:",
            "Reflection:",
            "Planning:",
            "Continuity:",
            "Analyze:",
            "Research:",
            "Plan:",
            "Reflect:",
            "Action:",
            "Delivery:"
        ]

        for label in sectionLabels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = #"(?<!^)(?<!\n)(\s*)\#(escaped)"#
            output = output.replacingOccurrences(
                of: pattern,
                with: "\n\n\(label)",
                options: .regularExpression
            )
        }

        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isReasoningOutcomePayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.hasPrefix("ReasoningOutcome:")
    }

    static func isControlMarkupOnly(_ text: String) -> Bool {
        let stripped = stripTextualToolCallMarkup(from: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stripped.isEmpty
    }

    private static func normalizeDisplayWhitespace(_ text: String) -> String {
        // Only strip leading/trailing whitespace — preserve all internal
        // spacing and newlines as the model intended.
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTextualToolCallMarkup(from text: String) -> String {
        guard !text.isEmpty else { return text }

        var output = text
        let patterns = [
            #"(?is)<tool_call>\s*.*?\s*</tool_call>"#,
            #"(?is)<tool_code>\s*.*?\s*</tool_code>"#,
            #"(?is)<arg_key>\s*.*?\s*</arg_key>"#,
            #"(?is)<arg_value>\s*.*?\s*</arg_value>"#,
            #"(?is)<minimax:tool_call>\s*.*?\s*</minimax:tool_call>"#,
            #"(?is)<invoke\s+name=\"[^\"]+\"\s*>.*?</invoke>"#,
            #"(?is)</?parameter\s+name=\"[^\"]+\"[^>]*>"#,
            #"(?is)</?param\s+name=\"[^\"]+\"[^>]*>"#,
            // Pipe-delimited tool call format: tool_name|{json}
            #"[a-z_]+\|[\[{][^}\]]*[\]}]"#,
            // Bare JSON tool call objects
            #"^\s*\{\s*"tool_calls"\s*:"#,
            #"^\s*\{\s*"name"\s*:\s*"[^"]+"\s*,"#,
            // Gemma 4 channel tags: <|channel> (pipe-left) and <channel|> (pipe-right)
            #"<\|channel>"#,
            #"<channel\|>"#,
            // Gemma 4 tool call block (closed): <|tool_call>...<tool_call|>
            #"(?is)<\|tool_call>.*?<tool_call\|>"#,
            // Gemma 4 tool call block (unclosed): <|tool_call> followed by 1-5 lines
            #"<\|tool_call>(?:[^\n]*\n?){1,5}"#,
            // Gemma 4 tool markers: <|tool>, <tool|>, <|tool_response>, <tool_response|>
            #"<\|tool>"#,
            #"<tool\|>"#,
            #"<\|tool_response>"#,
            #"<tool_response\|>"#,
            // Legacy Gemma channel format (pipe on both sides)
            #"<\|channel\|>\w+(?:\s*</\|channel\|>)?"#,
            // Legacy Gemma tool call format: call:name{...}
            #"call:\w+\{[^}]*\}"#,
            // DeepSeek/XML function call wrappers
            #"(?is)<\|tool_calls\|>.*?</\|tool_calls\|>"#,
            // Gemma function call XML tags
            #"(?is)<start_function_call>\s*.*?\s*<end_function_call>"#,
            // Turn markers: <|turn> and <turn|> (EOS)
            #"<\|turn>"#,
            #"<turn\|>"#,
            // String quote delimiter used in tool declarations
            #"<\|"\|>"#,
            // Thinking mode token
            #"<\|think\|>"#,
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }

        return output
    }

    private static func splitPlainReasoning(from text: String) -> (reasoning: String?, content: String)? {
        let pattern = #"(?s)^\s*(Reflection:\s*.*?\n\s*Continuity:.*?)(?:\n{1,2}|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              let reasoningRange = Range(match.range(at: 1), in: text),
              let removeRange = Range(match.range(at: 0), in: text) else {
            return nil
        }

        let reasoning = String(text[reasoningRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var remaining = text
        remaining.removeSubrange(removeRange)
        let cleaned = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return reasoning.isEmpty ? nil : (reasoning, cleaned)
    }

    private static func splitTaggedReasoning(from text: String) -> (reasoning: String?, content: String)? {
        // Gemma 4 channel-based reasoning: <|channel>thought\n...<channel|>
        // (id 100 soc_token opens, id 101 eoc_token closes)
        // The word "thought" + newline after the opening tag are literal.
        // Everything after <channel|> is content (no separate response tag).
        for prefix in ["<|channel>thought\n", "<|channel>thought"] {
            guard let open = text.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let afterOpen = text[open.upperBound...]
            guard let close = afterOpen.range(of: "<channel|>") else { continue }
            let reasoning = String(afterOpen[..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = String(text[close.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (reasoning.isEmpty ? nil : reasoning, remaining)
        }

        // Legacy: <|channel|>thought...<|channel|>response (both sides pipe, old format)
        if let gemmaThought = text.range(of: "<|channel|>thought", options: [.caseInsensitive]),
           let gemmaResponse = text.range(of: "<|channel|>response", options: [.caseInsensitive]),
           gemmaThought.upperBound < gemmaResponse.lowerBound {
            let reasoning = String(text[gemmaThought.upperBound..<gemmaResponse.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let content = String(text[gemmaResponse.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (reasoning.isEmpty ? nil : reasoning, content)
        }

        let tags = [
            ("<thinking>", "</thinking>"),
            ("<think>", "</think>"),
            ("<thought>", "</thought>"),
            ("<ide_reasoning>", "</ide_reasoning>")
        ]

        for (openingTag, closingTag) in tags {
            guard let openingRange = text.range(of: openingTag, options: [.caseInsensitive]) else {
                continue
            }

            let contentBeforeTag = String(text[..<openingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let afterOpeningTag = text[openingRange.upperBound...]

            if let closingRange = afterOpeningTag.range(of: closingTag, options: [.caseInsensitive]) {
                let reasoning = String(afterOpeningTag[..<closingRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let contentAfterTag = String(afterOpeningTag[closingRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let cleaned = [contentBeforeTag, contentAfterTag]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return reasoning.isEmpty ? nil : (reasoning, cleaned)
            }

            let reasoning = String(afterOpeningTag)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return reasoning.isEmpty ? nil : (reasoning, contentBeforeTag)
        }

        for (_, closingTag) in tags {
            guard let closingRange = text.range(of: closingTag, options: [.caseInsensitive]) else {
                continue
            }

            let reasoning = String(text[..<closingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let content = String(text[closingRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !reasoning.isEmpty {
                return (reasoning, content)
            }
        }

        return nil
    }

    /// Checks if a reasoning format correction is needed based on required sections.
    /// - Parameter text: The raw response text.
    /// - Returns: True if correction is needed.
    static func needsReasoningFormatCorrection(text: String) -> Bool {
        let split = splitReasoning(from: text)
        guard let reasoning = split.reasoning, !reasoning.isEmpty else { return false }

        let lowercasedReasoning = reasoning.lowercased()
        let modernRequired = ["reflection:", "planning:", "continuity:"]
        let legacyRequired = ["analyze:", "research:", "plan:", "reflect:", "action:", "delivery:"]

        let hasModern = modernRequired.contains(where: { lowercasedReasoning.contains($0) })
        if hasModern {
            return modernRequired.contains(where: { !lowercasedReasoning.contains($0) })
        }

        let hasLegacy = legacyRequired.contains(where: { lowercasedReasoning.contains($0) })
        if hasLegacy {
            return legacyRequired.contains(where: { !lowercasedReasoning.contains($0) })
        }

        return false
    }

    /// Checks if the reasoning block is present but low-quality (placeholders like "..." or no concrete content).
    /// This helps auto-retry with a stricter instruction.
    static func isLowQualityReasoning(text: String) -> Bool {
        let split = splitReasoning(from: text)
        guard let reasoning = split.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reasoning.isEmpty else {
            return false
        }

        if containsPlaceholderText(reasoning) {
            return true
        }

        // If it's tagged reasoning (e.g. <thought>), don't enforce strict header counts
        if splitTaggedReasoning(from: text) != nil {
            return false
        }

        let sections = extractReasoningSections(reasoning)
        guard !sections.isEmpty else { return true }

        let concreteCount = countConcreteReasoningSections(sections)
        return concreteCount < 2
    }

    private static func containsPlaceholderText(_ reasoning: String) -> Bool {
        let placeholders = [
            "Analyze:...",
            "Research:...",
            "Plan:...",
            "Reflect:...",
            "Action:...",
            "Delivery:..."
        ]
        return placeholders.contains(where: { reasoning.contains($0) })
    }

    private static func countConcreteReasoningSections(_ sections: [(key: String, value: String)]) -> Int {
        let badTokens = Set(["...", "…", "n/a", "na", "none", "nil"])
        return sections.filter { _, value in
            isConcreteReasoningValue(value, badTokens: badTokens)
        }.count
    }

    private static func isConcreteReasoningValue(_ value: String, badTokens: Set<String>) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.isEmpty { return false }
        if badTokens.contains(normalized) { return false }
        if normalized.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "") == "..." {
            return false
        }
        return normalized.count >= 6
    }

    private static func extractReasoningSections(_ reasoning: String) -> [(key: String, value: String)] {
        // Parse lines like "Analyze: ..."; tolerate leading/trailing whitespace.
        let lines = reasoning.split(whereSeparator: \.isNewline).map { String($0) }
        let keys = [
            "Analyze:", "Research:", "Plan:", "Reflect:", "Action:", "Delivery:",
            "Reflection:", "Planning:", "Continuity:"
        ]
        var results: [(String, String)] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let key = keys.first(where: { trimmed.lowercased().hasPrefix($0.lowercased()) }) {
                let value = String(trimmed.dropFirst(key.count))
                results.append((key, value))
            }
        }

        return results
    }

    static func reasoningOutcome(from reasoning: String) -> ReasoningOutcome? {
        let trimmed = reasoningForDisplay(reasoning).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sections = extractReasoningSections(trimmed)
        guard !sections.isEmpty else { return nil }

        func value(for key: String) -> String? {
            sections.first(where: { $0.key.lowercased().hasPrefix(key.lowercased()) })?
                .value
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let planDelta = value(for: "Plan:") ?? value(for: "Planning:")
        let nextAction = value(for: "Action:")
        let knownRisks = value(for: "Reflect:") ?? value(for: "Continuity:")

        let deliveryValue = (value(for: "Delivery:") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let deliveryState: ReasoningOutcomeDeliveryState
        if deliveryValue.contains("needs_work") || deliveryValue.contains("needs work") {
            deliveryState = .needs_work
        } else if deliveryValue.contains("done") || deliveryValue.contains("complete") {
            deliveryState = .done
        } else {
            deliveryState = .needs_work
        }

        return ReasoningOutcome(
            planDelta: planDelta?.isEmpty == false ? planDelta : nil,
            nextAction: nextAction?.isEmpty == false ? nextAction : nil,
            knownRisks: knownRisks?.isEmpty == false ? knownRisks : nil,
            deliveryState: deliveryState
        )
    }

    static func reasoningContainsImplementation(_ reasoning: String) -> Bool {
        let text = reasoning.lowercased()
        if text.isEmpty { return false }

        if text.contains("```") { return true }
        if text.contains("diff --git") { return true }
        if text.contains("*** begin patch") { return true }
        if text.contains("apply_patch") { return true }
        if text.contains("write_to_file") { return true }
        if text.contains("import ") && (text.contains("swift") || text.contains("typescript") || text.contains("python")) {
            return true
        }

        let strongSignals = [
            "here's the code",
            "here is the code",
            "implementation:",
            "code:",
            "final code",
            "new file",
            "updated file",
            "modified file",
            "changes:",
            "patch:",
            "diff:"
        ]
        if strongSignals.contains(where: { text.contains($0) }) {
            return true
        }

        return false
    }

    /// Determines if the AI's response indicates it should have emitted tool calls but didn't.
    /// - Parameter content: The AI response content.
    /// - Returns: True if a tool followup should be forced.
    static func shouldForceToolFollowup(content: String) -> Bool {
        let text = content.lowercased()
        if text.isEmpty { return false }

        if containsTextualToolCallMarkup(content) {
            return true
        }

        let triggers = [
            "i will implement",
            "i'll implement",
            "i will update",
            "i'll update",
            "i will patch",
            "i'll patch",
            "i will fix",
            "i'll fix",
            "i will resolve",
            "i'll resolve",
            "i am going to implement",
            "i'm going to implement",
            "next i will",
            "now i will"
        ]

        return triggers.contains(where: { text.contains($0) })
    }

    static func shouldForceExecutionFollowup(userInput: String, content: String, hasToolCalls: Bool) -> Bool {
        guard !hasToolCalls else { return false }
        guard userRequestRequiresExecution(userInput: userInput)
                || userRequestRequiresToolBackedInvestigation(userInput: userInput) else {
            return false
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if containsTextualToolCallMarkup(trimmed) {
            return true
        }

        let lower = trimmed.lowercased()

        let pendingExecutionSignals = [
            "i will",
            "i'll",
            "i am going to",
            "i'm going to",
            "next i will",
            "now i will",
            "let me",
            "i can",
            "next:",
            "next →",
            "→ next:",
            "path:"
        ]

        let hasPendingExecutionSignal = pendingExecutionSignals.contains(where: { lower.contains($0) })

        if hasPendingExecutionSignal {
            return true
        }

        if indicatesWorkWasPerformed(content: trimmed) {
            return false
        }

        let completionSignals = [
            "done",
            "completed",
            "finished",
            "all set",
            "resolved"
        ]
        if completionSignals.contains(where: { lower.contains($0) }) {
            return false
        }

        return false
    }

    static func containsTextualToolCallMarkup(_ content: String) -> Bool {
        let lower = content.lowercased()
        return lower.contains("<tool_call>")
            || lower.contains("<tool_code>")
            || lower.contains("<minimax:tool_call>")
            || lower.contains("<invoke name=")
            || lower.contains("<param name=")
            || lower.contains("<arg_key>")
            || lower.contains("<arg_value>")
    }

    static func hasMissingClaimedFileArtifacts(content: String, projectRoot: URL) -> Bool {
        guard indicatesWorkWasPerformed(content: content) else { return false }

        let claimedArtifacts = claimedFileArtifacts(in: content)
        guard !claimedArtifacts.isEmpty else { return false }

        return claimedArtifacts.contains { artifact in
            !projectContainsClaimedArtifact(artifact, projectRoot: projectRoot)
        }
    }

    static func indicatesWorkWasPerformed(content: String) -> Bool {
        let text = content.lowercased()
        if text.isEmpty { return false }

        let directClaims = [
            "i implemented",
            "i've implemented",
            "i have implemented",
            "implemented ",
            "i updated",
            "i've updated",
            "i have updated",
            "updated ",
            "i patched",
            "i've patched",
            "i have patched",
            "patched ",
            "i fixed",
            "i've fixed",
            "i have fixed",
            "fixed ",
            "i changed",
            "i've changed",
            "i have changed",
            "changed ",
            "i added",
            "i've added",
            "i have added",
            "added ",
            "i created",
            "i've created",
            "i have created",
            "created ",
            "i removed",
            "i've removed",
            "i have removed",
            "removed ",
            "i refactored",
            "i've refactored",
            "i have refactored",
            "refactored "
        ]

        if directClaims.contains(where: { text.contains($0) }) {
            return true
        }

        let artifactClaims = [
            "here's the diff",
            "here is the diff",
            "here's a patch",
            "here is a patch",
            "i committed",
            "i pushed",
            "updated file",
            "modified file",
            "created file",
            "changed file",
            "applied patch",
            "all required files have been created",
            "all requested files have been created",
            "application structure is now in place",
            "todo application structure is now in place",
            "task complete."
        ]

        return artifactClaims.contains(where: { text.contains($0) })
    }

    private static func claimedFileArtifacts(in content: String) -> [String] {
        let pattern = #"(?<![A-Za-z0-9_./-])([A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8})(?![A-Za-z0-9_./-])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)

        var results: [String] = []
        var seen: Set<String> = []
        for match in regex.matches(in: content, options: [], range: range) {
            guard let tokenRange = Range(match.range(at: 1), in: content) else { continue }
            let rawToken = String(content[tokenRange])
            let token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[](){}<>.,;:"))
            guard isLikelyProjectArtifactToken(token) else { continue }
            if seen.insert(token).inserted {
                results.append(token)
            }
        }

        return results
    }

    private static func isLikelyProjectArtifactToken(_ token: String) -> Bool {
        let lowered = token.lowercased()
        guard !lowered.hasPrefix("http://"), !lowered.hasPrefix("https://") else { return false }
        guard lowered.contains(".") else { return false }
        return true
    }

    private static func projectContainsClaimedArtifact(_ artifact: String, projectRoot: URL) -> Bool {
        let normalizedArtifact = NSString(string: artifact).standardizingPath
        let directURL = projectRoot.appendingPathComponent(normalizedArtifact).standardizedFileURL
        if FileManager.default.fileExists(atPath: directURL.path) {
            return true
        }

        guard !normalizedArtifact.contains("/") else {
            return false
        }

        let enumerator = FileManager.default.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        )

        while let next = enumerator?.nextObject() as? URL {
            if next.path.contains("/.ide/") {
                enumerator?.skipDescendants()
                continue
            }
            guard next.lastPathComponent == normalizedArtifact else { continue }
            let isRegularFile = (try? next.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isRegularFile {
                return true
            }
        }

        return false
    }

    static func userRequestRequiresExecution(userInput: String) -> Bool {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return false }

        let continuationExecutionPatterns = [
            #"^(please\s+)?continue\b"#,
            #"^(please\s+)?proceed\b"#,
            #"^(please\s+)?go ahead\b"#,
            #"^(please\s+)?resume\b"#,
            #"^(please\s+)?recover(\s+and\s+continue)?\b"#,
            #"\bfinish( it up)?\b.{0,80}\b(implementation|feature|dashboard|page|flow|setup|migration|task)\b"#,
            #"\bresolve\b.{0,80}\b(dependency|dependencies|conflict|conflicts|issue|issues|problem|problems|error|errors|failure|failures)\b"#,
            #"\binstall\b.{0,80}\b(dependency|dependencies|package|packages|plugin|plugins|tool|tools)\b"#
        ]
        if continuationExecutionPatterns.contains(where: { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }) {
            return true
        }

        let executionTriggers = [
            "implement",
            "fix",
            "refactor",
            "add ",
            "remove ",
            "delete ",
            "rename",
            "move ",
            "update ",
            "change ",
            "migrate",
            "wire up",
            "hook up",
            "integrate",
            "run tests",
            "build",
            "compile",
            "deploy",
            "write ",
            "create ",
            "generate ",
            "scaffold",
            "set up",
            "setup",
            "process ",
            "continue ",
            "proceed ",
            "resume ",
            "create file",
            "edit file",
            "apply patch"
        ]

        if executionTriggers.contains(where: { text.contains($0) }) {
            return true
        }

        let executionPatterns = [
            #"\b(create|write|generate|make|update|modify|delete|remove|process)\b.{0,80}\b(file|files|folder|directory|project|script|report|summary)\b"#,
            #"\b(read|analyze)\b.{0,80}\b(file|files)\b.{0,80}\b(create|write|generate|produce)\b"#,
            #"\b(run|execute)\b.{0,80}\b(command|commands|test|tests|build)\b"#
        ]

        if executionPatterns.contains(where: { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }) {
            return true
        }

        let analysisOnlyTriggers = [
            "explain",
            "why",
            "what is",
            "what does",
            "how does",
            "help me understand",
            "summarize",
            "review",
            "analyze",
            "compare",
            "pros and cons",
            "tradeoffs",
            "best approach",
            "recommend"
        ]

        if analysisOnlyTriggers.contains(where: { text.contains($0) }) {
            return false
        }

        // Default to analysis-only unless the user explicitly requests execution.
        return false
    }

    static func userRequestRequiresToolBackedInvestigation(userInput: String) -> Bool {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return false }

        let directTriggers = [
            "audit",
            "codebase audit",
            "project overview",
            "review the app",
            "review the project",
            "review the codebase",
            "inspect the app",
            "inspect the project",
            "inspect the codebase",
            "analyze the app",
            "analyze the project",
            "analyze the codebase",
            "perform audit",
            "areas for improvement"
        ]
        if directTriggers.contains(where: { text.contains($0) }) {
            return true
        }

        let investigationPatterns = [
            #"\b(review|audit|inspect|analyze)\b.{0,80}\b(app|project|codebase|repository|repo|files|implementation|architecture)\b"#,
            #"\b(project overview|codebase overview|architecture overview)\b"#,
            #"\b(constructive critique|areas for improvement|improvement areas)\b"#
        ]

        return investigationPatterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        }
    }

    static func isRequestingUserInputForNextStep(content: String) -> Bool {
        let text = content.lowercased()
        if text.isEmpty { return false }

        let triggers = [
            "please provide",
            "can you provide",
            "please share",
            "can you share",
            "paste",
            "send me",
            "show me",
            "what is the diff",
            "provide the diff",
            "share the diff",
            "need your input",
            "need more information",
            "which option",
            "which one",
            "should i proceed",
            "do you want me to"
        ]

        return triggers.contains(where: { text.contains($0) })
    }

    /// Determines whether the response indicates delivery is complete.
    /// Returns .needsWork if the Delivery section is missing or does not mark completion.
    static func deliveryStatus(from text: String) -> DeliveryStatus? {
        let split = splitReasoning(from: text)
        guard let reasoning = split.reasoning, !reasoning.isEmpty else { return nil }

        let sections = extractReasoningSections(reasoning)
        guard let deliveryLine = sections.first(where: { $0.key.lowercased().hasPrefix("delivery:") })?.value else {
            return nil
        }

        let normalized = deliveryLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let needsWorkTokens = [
            "needs_work",
            "needs work",
            "not done",
            "in_progress",
            "in progress"
        ]
        let doneTokens = [
            "done",
            "complete",
            "completed"
        ]

        if containsAnyToken(needsWorkTokens, in: normalized) {
            // Check for conflicting completion signals in the reasoning text itself
            let lowerReasoning = reasoning.lowercased()
            if lowerReasoning.contains("all set") ||
                lowerReasoning.contains("done for now") ||
                (lowerReasoning.contains("no pending tasks") && !lowerReasoning.contains("remaining")) {
                return .done
            }
            return .needsWork
        }
        
        if containsAnyToken(doneTokens, in: normalized) {
            return .done
        }

        // Fallback: search entire raw text (case-insensitive)
        let overall = text.lowercased()
        if overall.contains("delivery: done") || overall.contains("delivery: complete") {
            return .done
        }
        if overall.contains("delivery: needs_work") || overall.contains("delivery: needs work") {
            return .needsWork
        }

        return nil
    }

    private static func containsAnyToken(_ tokens: [String], in text: String) -> Bool {
        tokens.contains(where: text.contains)
    }
    
    /// Checks if the content contains only reasoning without any actual response
    static func isReasoningOnly(content: String) -> Bool {
        let split = splitReasoning(from: content)
        let hasReasoning = split.reasoning?.isEmpty == false
        let hasContent = !(split.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        return hasReasoning && !hasContent
    }
}
