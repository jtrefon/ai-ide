import Foundation

func patchFile(path: String, target: String, replacement: String) throws {
    var content = try String(contentsOfFile: path, encoding: .utf8)
    content = content.replacingOccurrences(of: target, with: replacement)
    try content.write(toFile: path, atomically: true, encoding: .utf8)
}

try patchFile(
    path: "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/Orchestration/Nodes/FinalResponseNode.swift",
    target: "func run(state: OrchestrationState) async throws -> OrchestrationState {",
    replacement: """
    func run(state: OrchestrationState) async throws -> OrchestrationState {
        print("====== FinalResponseNode RUN ======")
"""
)

try patchFile(
    path: "/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ConversationFlow/ToolLoopHandler.swift",
    target: "func handleToolLoopIfNeeded(",
    replacement: """
    func handleToolLoopIfNeeded(
"""
)

