//
//  ChatPromptBuilder.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation

/// Responsible for constructing and formatting prompts for the AI service.
class ChatPromptBuilder {

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
        let required = ["analyze:", "research:", "plan:", "reflect:"]
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

        // If the model literally copied placeholder example text, treat as low quality.
        if reasoning.contains("Analyze:...") ||
            reasoning.contains("Research:...") ||
            reasoning.contains("Plan:...") ||
            reasoning.contains("Reflect:...") {
            return true
        }

        let sections = extractReasoningSections(reasoning)
        guard sections.isEmpty == false else { return true }

        let badTokens = Set(["...", "…", "n/a", "na", "none", "nil"])
        var concreteCount = 0

        for (_, value) in sections {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if normalized.isEmpty { continue }
            if badTokens.contains(normalized) { continue }
            if normalized.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "") == "..." {
                continue
            }

            // Heuristic: require some actual text beyond a couple of characters.
            if normalized.count >= 6 {
                concreteCount += 1
            }
        }

        // Require at least 2 sections with concrete content.
        return concreteCount < 2
    }

    private static func extractReasoningSections(_ reasoning: String) -> [(key: String, value: String)] {
        // Parse lines like "Analyze: ..."; tolerate leading/trailing whitespace.
        let lines = reasoning.split(whereSeparator: \.isNewline).map { String($0) }
        let keys = ["Analyze:", "Research:", "Plan:", "Reflect:"]
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
}
