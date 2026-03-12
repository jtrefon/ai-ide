import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/FinalResponseHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let target = """
        let template = try PromptRepository.shared.prompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            projectRoot: projectRoot
        )
"""
let replacement = """
        let template = try PromptRepository.shared.fallbackPrompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            defaultValue: Self.defaultFinalResponsePrompt,
            allowFallback: true,
            projectRoot: projectRoot
        )
"""

if content.contains(target) {
    content = content.replacingOccurrences(of: target, with: replacement)
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Patched successfully")
} else {
    print("Target not found. Let's search for similar text.")
    if let range = content.range(of: "PromptRepository.shared.") {
        let snippet = content[range.lowerBound...].prefix(200)
        print("Found: \\(snippet)")
    }
}
