import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/FinalResponseHandler.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

let target = """
    private func buildFinalResponsePrompt(
        followupReason: String,
        toolSummary: String,
        projectRoot: URL,
        conversationId: String
    ) async throws -> String {
        let template = try PromptRepository.shared.prompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            projectRoot: projectRoot
        )
"""

let replacement = """
    private static let defaultFinalResponsePrompt = \"\"\"
# Final Summary Contract

{{followup_reason}}

Provide a concise final user-facing summary of the completed work.
Do NOT call any tools.

Context:
{{tool_summary}}

Plan:
{{plan_markdown}}
\"\"\"

    private func buildFinalResponsePrompt(
        followupReason: String,
        toolSummary: String,
        projectRoot: URL,
        conversationId: String
    ) async throws -> String {
        let template = try PromptRepository.shared.fallbackPrompt(
            key: "ConversationFlow/FinalResponse/final_response_summary",
            defaultValue: Self.defaultFinalResponsePrompt,
            allowFallback: true,
            projectRoot: projectRoot
        )
"""

content = content.replacingOccurrences(of: target, with: replacement)
try content.write(toFile: path, atomically: true, encoding: .utf8)
