//
//  StreamingOutputBuffer.swift
//  osx-ide
//
//  Created by AI Assistant on 25/06/2026.
//

import Foundation

/// Structured streaming buffer that classifies incoming model output into
/// content, reasoning, and tool-text containers before rendering.
/// This prevents raw tool-call text from appearing in the chat content
/// and avoids glitchy UI caused by displaying then removing large chunks.
@MainActor
final class StreamingOutputBuffer {

    // MARK: - Containers

    /// Visible text content (markdown, user-facing replies)
    private(set) var content: String = ""

    /// Reasoning text (chain-of-thought, thinking blocks)
    private(set) var reasoning: String = ""

    /// Raw text that looks like tool calls but hasn't been parsed yet.
    /// Held separately so it doesn't appear in content.
    private(set) var toolText: String = ""

    // MARK: - Internal State

    /// Accumulated raw text from content stream, before classification
    private var rawContent: String = ""

    /// Accumulated raw text from reasoning stream
    private var rawReasoning: String = ""

    /// Whether we're currently inside a thinking/reasoning block in content
    private var insideThinkingBlock: Bool = false

    /// Buffer for detecting thinking tags
    private var pendingTagCheck: String = ""

    // MARK: - Configuration

    /// Minimum chars to accumulate before attempting classification
    private let classificationThreshold = 40

    /// Known thinking block markers
    private static let thinkingOpenTag = "<think>"
    private static let thinkingCloseTag = "</think>"

    // MARK: - Append

    /// Append a content chunk from the model's streaming output
    func appendContent(_ chunk: String) {
        rawContent.append(chunk)
        reclassifyContent()
    }

    /// Append a reasoning chunk from the model's reasoning stream
    func appendReasoning(_ chunk: String) {
        rawReasoning.append(chunk)
        reasoning = rawReasoning
    }

    // MARK: - Classification

    /// Reclassify raw content into content vs tool-text vs thinking blocks
    private func reclassifyContent() {
        // If we have reasoning coming from a separate stream, content is all visible
        if !rawReasoning.isEmpty {
            content = rawContent
            toolText = ""
            return
        }

        // Check for thinking blocks in content stream
        let classified = classifyThinkingBlocks(rawContent)
        content = classified.content
        reasoning = classified.reasoning.isEmpty ? rawReasoning : (rawReasoning.isEmpty ? classified.reasoning : rawReasoning + "\n" + classified.reasoning)

        // Detect tool-call-like text patterns
        let toolDetection = detectToolTextPatterns(classified.content)
        content = toolDetection.content
        toolText = toolDetection.toolText
    }

    /// Extract <think>...</think> blocks from content
    private func classifyThinkingBlocks(_ text: String) -> (content: String, reasoning: String) {
        var content = ""
        var reasoning = ""
        var remaining = text

        while let openRange = remaining.range(of: Self.thinkingOpenTag) {
            content += remaining[remaining.startIndex..<openRange.lowerBound]
            let afterOpen = remaining[openRange.upperBound...]

            if let closeRange = afterOpen.range(of: Self.thinkingCloseTag) {
                reasoning += afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
                remaining = String(afterOpen[closeRange.upperBound...])
            } else {
                reasoning += String(afterOpen)
                remaining = ""
            }
        }

        content += remaining
        return (content, reasoning)
    }

    /// Detect text that looks like unparsed tool calls and separate it
    private func detectToolTextPatterns(_ text: String) -> (content: String, toolText: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Patterns that indicate tool-call text, not user-visible content
        let toolPatterns: [String] = [
            "\"name\":",
            "\"arguments\":",
            "\"function\":",
            "\"type\": \"function\"",
            "tool_calls",
        ]

        // Classify as tool text if content starts with { and contains at least 2 tool patterns
        let matchCount = toolPatterns.filter { pattern in
            trimmed.lowercased().contains(pattern.lowercased())
        }.count

        if matchCount >= 2 && trimmed.hasPrefix("{") {
            return ("", text)
        }

        return (text, "")
    }

    // MARK: - Access

    /// True if there's any content to render
    var hasContent: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True if there's any reasoning to render
    var hasReasoning: Bool {
        !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True if there's tool text held back from rendering
    var hasToolText: Bool {
        !toolText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Reset

    /// Clear all containers
    func clear() {
        content = ""
        reasoning = ""
        toolText = ""
        rawContent = ""
        rawReasoning = ""
        insideThinkingBlock = false
        pendingTagCheck = ""
    }
}
