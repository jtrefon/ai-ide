import XCTest
@testable import osx_ide

@MainActor
final class ReasoningAndToolArgumentRegressionTests: XCTestCase {
    func testAgentReasoningPromptIsDisabledForStrategicPlanning() {
        let promptKey = AIRequestStage.reasoningPromptKeyIfNeeded(
            reasoningMode: .agent,
            mode: .agent,
            stage: .strategic_planning
        )

        XCTAssertNil(promptKey)
    }

    func testWriteFileArgumentsRecoverTruncatedContentFromRawChunk() async {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)

        let resolver = ToolArgumentResolver(
            fileSystemService: FileSystemService(),
            projectRoot: projectRoot
        )
        let toolCall = AIToolCall(
            id: "call_write_truncated",
            name: "write_file",
            arguments: [
                "_raw_args_chunk": "\"path\":\"src/App.tsx\",\"content\":\"import React from 'react';\\nexport default function App() { return <div>Hello</div>; }"
            ]
        )

        let mergedArguments = await resolver.buildMergedArguments(
            toolCall: toolCall,
            conversationId: "conversation"
        )

        XCTAssertEqual(mergedArguments["path"] as? String, "src/App.tsx")
        XCTAssertEqual(
            mergedArguments["content"] as? String,
            "import React from 'react';\nexport default function App() { return <div>Hello</div>; }"
        )
    }
}
