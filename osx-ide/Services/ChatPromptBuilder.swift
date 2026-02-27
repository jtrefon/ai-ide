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
    /// strips reasoning tags and tool-control XML-like markup while preserving paragraph breaks.
    static func contentForDisplay(from text: String) -> String {
        let split = splitReasoning(from: text)
        let withoutControl = stripToolControlMarkup(from: split.content)
        return normalizeDisplayWhitespace(withoutControl)
    }

    static func isControlMarkupOnly(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let hasToolMarkup = lowered.contains("<tool_call>") || lowered.contains("<arg_key>") || lowered.contains("<arg_value>")
        guard hasToolMarkup else { return false }
        return contentForDisplay(from: text).isEmpty
    }

    private static func stripToolControlMarkup(from text: String) -> String {
        var output = text
        let patterns = [
            #"(?is)<tool_call>\s*.*?\s*</tool_call>"#,
            #"(?is)<arg_key>\s*.*?\s*</arg_key>"#,
            #"(?is)<arg_value>\s*.*?\s*</arg_value>"#,
            #"(?is)</?tool_call>"#,
            #"(?is)</?arg_key>"#,
            #"(?is)</?arg_value>"#
        ]

        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "\n\n", options: .regularExpression)
        }
        return output
    }

    private static func normalizeDisplayWhitespace(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If words were glued by model glitches around punctuation-less boundaries, ensure at least single spaces.
        output = output.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        return output
    }

    private static func splitTaggedReasoning(from text: String) -> (reasoning: String?, content: String)? {
        let taggedPattern = #"(?is)<ide_reasoning>\s*(.*?)\s*</ide_reasoning>"#
        guard let regex = try? NSRegularExpression(pattern: taggedPattern) else { return nil }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)

        var reasoningBlocks: [String] = []
        var remaining = text

        // Replace complete blocks with paragraph separators to avoid gluing content.
        for match in matches.reversed() {
            if match.numberOfRanges > 1, let blockRange = Range(match.range(at: 1), in: text) {
                let block = String(text[blockRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    reasoningBlocks.append(block)
                }
            }
            if let fullBlockRange = Range(match.range(at: 0), in: remaining) {
                remaining.replaceSubrange(fullBlockRange, with: "\n\n")
            }
        }

        reasoningBlocks.reverse()

        // Recover and strip partial reasoning block if opening tag exists without closing tag.
        let startTag = "<ide_reasoning>"
        let endTag = "</ide_reasoning>"
        let hasStartTag = remaining.range(of: startTag, options: .caseInsensitive) != nil
        let hasEndTag = remaining.range(of: endTag, options: .caseInsensitive) != nil

        if hasStartTag && !hasEndTag,
           let openRange = remaining.range(of: startTag, options: .caseInsensitive) {
            let trailing = remaining[openRange.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailing.isEmpty {
                reasoningBlocks.append(String(trailing))
            }
            remaining.replaceSubrange(openRange.lowerBound..<remaining.endIndex, with: "\n\n")
        }

        // Remove orphan closing tag fragments from leaked/incomplete outputs.
        remaining = remaining.replacingOccurrences(
            of: #"(?is)</ide_reasoning>"#,
            with: "\n\n",
            options: .regularExpression
        )
        remaining = remaining.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        let reasoning = reasoningBlocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        if reasoning.isEmpty && cleaned == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            return nil
        }

        return (reasoning.isEmpty ? nil : reasoning, cleaned)
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
        let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let triggers = [
            "i will implement",
            "i'll implement",
            "i will update",
            "i'll update",
            "i will patch",
            "i'll patch",
            "i will fix",
            "i'll fix",
            "i am going to implement",
            "i'm going to implement",
            "next i will",
            "now i will"
        ]

        return triggers.contains(where: { text.contains($0) })
    }

    static func shouldForceExecutionFollowup(userInput: String, content: String, hasToolCalls: Bool) -> Bool {
        guard !hasToolCalls else { return false }
        guard userRequestRequiresExecution(userInput: userInput) else { return false }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return true
    }

    static func indicatesWorkWasPerformed(content: String) -> Bool {
        let text = content.lowercased()
        if text.isEmpty { return false }

        let directClaims = [
            "i implemented",
            "i've implemented",
            "i have implemented",
            "i updated",
            "i've updated",
            "i have updated",
            "i patched",
            "i've patched",
            "i have patched",
            "i fixed",
            "i've fixed",
            "i have fixed",
            "i changed",
            "i've changed",
            "i have changed",
            "i added",
            "i've added",
            "i have added",
            "i created",
            "i've created",
            "i have created",
            "i removed",
            "i've removed",
            "i have removed",
            "i refactored",
            "i've refactored",
            "i have refactored"
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
            "applied patch"
        ]

        return artifactClaims.contains(where: { text.contains($0) })
    }

    static func userRequestRequiresExecution(userInput: String) -> Bool {
        let text = userInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return false }

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
            "create file",
            "edit file",
            "apply patch"
        ]

        if executionTriggers.contains(where: { text.contains($0) }) {
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
            return .needsWork
        }

        return containsAnyToken(doneTokens, in: normalized) ? .done : .needsWork
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
