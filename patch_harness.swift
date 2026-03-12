import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ideHarnessTests/ToolLoopDropoutHarnessTests.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)

// Let's add a do-catch block around the send to see if it throws
if let range = content.range(of: """
        try await sendCoordinator.send(SendRequest(
            userInput: "Implement login page end-to-end",
            explicitContext: nil,
            mode: .agent,
            projectRoot: projectRoot,
            conversationId: conversationId,
            runId: UUID().uuidString,
            availableTools: [FakeTool(name: "fake_tool")],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        ))
""") {
    content.replaceSubrange(range, with: """
        do {
            try await sendCoordinator.send(SendRequest(
                userInput: "Implement login page end-to-end",
                explicitContext: nil,
                mode: .agent,
                projectRoot: projectRoot,
                conversationId: conversationId,
                runId: UUID().uuidString,
                availableTools: [FakeTool(name: "fake_tool")],
                cancelledToolCallIds: { [] },
                qaReviewEnabled: false,
                draftAssistantMessageId: nil
            ))
        } catch {
            print("SEND ERROR: \\(error)")
        }
""")
    try content.write(toFile: path, atomically: true, encoding: .utf8)
    print("Patched test")
} else {
    print("Could not find the target code to patch")
}
