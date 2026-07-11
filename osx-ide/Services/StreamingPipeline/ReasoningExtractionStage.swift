import Foundation

public final class ReasoningExtractionStage: @unchecked Sendable {
    public let identifier = "reasoning_extraction"

    private var pendingBuffer: String = ""

    private typealias Extractor = (String) -> ReasoningResult?
    private typealias ReasoningResult = (before: String?, reasoning: String?, after: String?, isPartial: Bool)

    private let extractors: [Extractor] = [
        ReasoningExtractionStage.extractGemma4Reasoning,
        ReasoningExtractionStage.extractLegacyGemmaReasoning,
        ReasoningExtractionStage.extractTaggedReasoning(open: "<think>", close: "</think>"),
        ReasoningExtractionStage.extractTaggedReasoning(open: "<thinking>", close: "</thinking>"),
        ReasoningExtractionStage.extractTaggedReasoning(open: "<thought>", close: "</thought>"),
        ReasoningExtractionStage.extractTaggedReasoning(open: "<ide_reasoning>", close: "</ide_reasoning>"),
        ReasoningExtractionStage.extractClosingTagOnlyReasoning,
    ]

    public init() {}
}

extension ReasoningExtractionStage: PipelineStage {

    public func process(_ event: PipelineEvent) -> [PipelineEvent] {
        switch event {
        case .segment(let segment) where segment.kind == .userVisible:
            return processText(segment.text, source: segment.source)
        case .segment(let segment) where segment.kind == .reasoning:
            return [event]
        default:
            return [event]
        }
    }

    public func flush() -> [PipelineEvent] {
        guard !pendingBuffer.isEmpty else { return [] }
        let text = pendingBuffer
        pendingBuffer = ""
        return [.segment(Segment(kind: .userVisible, text: text, source: "reasoning_stage"))]
    }

    private func processText(_ text: String, source: String) -> [PipelineEvent] {
        let combined = pendingBuffer + text
        pendingBuffer = ""

        guard let result = extractReasoning(from: combined) else {
            return [.segment(Segment(kind: .userVisible, text: combined, source: source))]
        }

        // Partial result (opening tag without closing tag) → buffer
        if result.isPartial {
            pendingBuffer = combined
            if pendingBuffer.count > 16_384 {
                let flush = String(pendingBuffer.prefix(16_384))
                pendingBuffer = String(pendingBuffer.dropFirst(16_384))
                return [.segment(Segment(kind: .userVisible, text: flush, source: source))]
            }
            return []
        }

        var events = [PipelineEvent]()
        if let before = result.before, !before.isEmpty {
            events.append(.segment(Segment(kind: .userVisible, text: before, source: source)))
        }
        if let reasoning = result.reasoning, !reasoning.isEmpty {
            events.append(.segment(Segment(kind: .reasoning, text: reasoning, source: source)))
        }
        if let after = result.after {
            let tail = processText(after, source: source)
            events.append(contentsOf: tail)
        }
        return events
    }

    private func extractReasoning(from text: String) -> ReasoningResult? {
        for extractor in extractors {
            if let result = extractor(text) {
                return result
            }
        }
        return nil
    }
}

// MARK: - Extractors (static)

extension ReasoningExtractionStage {

    private static func extractGemma4Reasoning(from text: String) -> ReasoningResult? {
        for prefix in ["<|channel>thought\n", "<|channel>thought"] {
            guard let open = text.range(of: prefix, options: [.caseInsensitive]) else { continue }
            let afterOpen = text[open.upperBound...]
            guard let close = afterOpen.range(of: "<channel|>") else { continue }
            let reasoning = String(afterOpen[..<close.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = String(text[close.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, reasoning.isEmpty ? nil : reasoning, remaining, false)
        }
        return nil
    }

    private static func extractLegacyGemmaReasoning(from text: String) -> ReasoningResult? {
        guard let thought = text.range(of: "<|channel|>thought", options: [.caseInsensitive]),
              let response = text.range(of: "<|channel|>response", options: [.caseInsensitive]),
              thought.upperBound < response.lowerBound else { return nil }
        let reasoning = String(text[thought.upperBound..<response.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(text[response.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (nil, reasoning.isEmpty ? nil : reasoning, content, false)
    }

    private static func extractTaggedReasoning(open: String, close: String) -> Extractor {
        return { text in
            guard let openingRange = text.range(of: open, options: [.caseInsensitive]) else {
                return nil
            }
            let before = String(text[..<openingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let afterOpen = text[openingRange.upperBound...]

            if let closingRange = afterOpen.range(of: close, options: [.caseInsensitive]) {
                let reasoning = String(afterOpen[..<closingRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let after = String(afterOpen[closingRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (before.isEmpty ? nil : before, reasoning.isEmpty ? nil : reasoning, after, false)
            }

            // Opening tag present but no closing tag → partial
            let reasoning = String(afterOpen)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (before.isEmpty ? nil : before, reasoning.isEmpty ? nil : reasoning, nil, true)
        }
    }

    private static func extractClosingTagOnlyReasoning(from text: String) -> ReasoningResult? {
        let closeTags = ["</think>", "</thinking>", "</thought>", "</ide_reasoning>"]
        for (_, close) in closeTags.enumerated() {
            guard let closingRange = text.range(of: close, options: [.caseInsensitive]) else {
                continue
            }
            let reasoning = String(text[..<closingRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(text[closingRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !reasoning.isEmpty {
                return (nil, reasoning, after, false)
            }
        }
        return nil
    }
}
