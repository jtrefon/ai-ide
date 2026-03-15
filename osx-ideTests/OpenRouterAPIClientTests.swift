import XCTest
@testable import osx_ide

final class OpenRouterAPIClientTests: XCTestCase {
    func testSSEPayloadsJoinMultilineDataEvents() {
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"<think>\"}}",
            "data: ,\"usage\":{\"prompt_tokens\":1}}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"done\"}}]}",
            "",
            "data: [DONE]"
        ]

        let payloads = OpenRouterAPIClient.ssePayloads(from: lines)

        XCTAssertEqual(payloads.count, 3)
        XCTAssertEqual(
            payloads[0],
            "{\"choices\":[{\"delta\":{\"content\":\"<think>\"}}\n,\"usage\":{\"prompt_tokens\":1}}"
        )
        XCTAssertEqual(payloads[1], "{\"choices\":[{\"delta\":{\"content\":\"done\"}}]}")
        XCTAssertEqual(payloads[2], "[DONE]")
    }

    func testOpenRouterServiceRecoversMinimaxToolCallMarkup() {
        let content = """
        Completed useTodos hook created Next: reviewing retrieved context and finalizing when the objective is satisfied in src/components.
        <minimax:tool_call>
        <invoke name="list_files">
        <parameter name="path">/tmp/project/src/components</parameter>
        </invoke>
        </minimax:tool_call>
        """

        let toolCalls = OpenRouterAIService.extractFallbackToolCalls(from: content)

        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?.first?.name, "list_files")
        XCTAssertEqual(toolCalls?.first?.arguments["path"] as? String, "/tmp/project/src/components")
    }
}
