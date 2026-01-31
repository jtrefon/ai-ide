import Foundation

class ChatPromptBuilder {
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
}

let toolReasoningPrefix =
    "<ide_reasoning>Analyze: Details\nResearch: Details\nPlan: Details\n" +
    "Reflect: Details</ide_reasoning>"
let response = toolReasoningPrefix + "Done"
let split = ChatPromptBuilder.splitReasoning(from: response)
print("Response: \(response)")
print("Split: reasoning='\(split.reasoning ?? "nil")', content='\(split.content)'")
