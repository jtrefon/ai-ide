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

        let startTag = "<ide_reasoning>"
        let endTag = "</ide_reasoning>"

        guard let startRange = text.range(of: startTag),
              let endRange = text.range(of: endTag) else {
            return (nil, text)
        }

        guard startRange.lowerBound < endRange.lowerBound else {
            return (nil, text)
        }

        let reasoningStart = startRange.upperBound
        let reasoningEnd = endRange.lowerBound
        let reasoning = String(text[reasoningStart..<reasoningEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

        var remaining = text
        remaining.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        let cleaned = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        return (reasoning.isEmpty ? nil : reasoning, cleaned)
    }

    /// Checks if a reasoning format correction is needed based on required sections.
    /// - Parameter text: The raw response text.
    /// - Returns: True if correction is needed.
    static func needsReasoningFormatCorrection(text: String) -> Bool {
        let split = splitReasoning(from: text)
        guard let reasoning = split.reasoning, !reasoning.isEmpty else { return false }

        let lowercasedReasoning = reasoning.lowercased()
        let required = ["analyze:", "research:", "plan:", "reflect:", "action:", "delivery:"]
        return required.contains(where: { !lowercasedReasoning.contains($0) })
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
        let keys = ["Analyze:", "Research:", "Plan:", "Reflect:", "Action:", "Delivery:"]
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

        let planDelta = value(for: "Plan:")
        let nextAction = value(for: "Action:")
        let knownRisks = value(for: "Reflect:")

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
            return .needsWork
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
}
