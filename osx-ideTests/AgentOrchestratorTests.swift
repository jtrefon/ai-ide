import XCTest
import Combine
@testable import osx_ide

@MainActor
final class AgentOrchestratorTests: XCTestCase {
    private actor Counter {
        private(set) var sendCount: Int = 0
        private(set) var verifyToolExecutions: Int = 0

        func incrementSend() { sendCount += 1 }
        func incrementVerifyToolExecutions() { verifyToolExecutions += 1 }
    }

    private struct FakeTool: AITool {
        let name: String
        let description: String = "fake"
        var parameters: [String : Any] { ["type": "object", "properties": [:]] }
        let response: String

        func execute(arguments _: [String : Any]) async throws -> String {
            response
        }
    }

    private func makeAllowlistSend() -> @Sendable (AgentOrchestrator.SendRequest) async throws -> AIServiceResponse {
        { request in
            let hasVerifier = request.messages.contains(where: { $0.role == .system && $0.content.contains("Verifier role") })
            if hasVerifier {
                return AIServiceResponse(
                    content: "verify",
                    toolCalls: [AIToolCall(id: UUID().uuidString, name: "run_command", arguments: ["command": "rm -rf /tmp/nope"]) ]
                )
            }
            return AIServiceResponse(content: "ok", toolCalls: nil)
        }
    }

    private func makeAllowlistExecuteTools() -> @Sendable (AgentOrchestrator.ToolExecutionRequest) async -> [ChatMessage] {
        { request in
            guard let runTool = request.tools.first(where: { $0.name == "run_command" }) else { return [] }
            return await withTaskGroup(of: ChatMessage.self) { group in
                for call in request.toolCalls {
                    group.addTask {
                        do {
                            _ = try await runTool.execute(arguments: call.arguments)
                            return ChatMessage(role: .tool, content: "should not succeed")
                        } catch {
                            return ChatMessage(role: .tool, content: error.localizedDescription)
                        }
                    }
                }
                var results: [ChatMessage] = []
                for await msg in group { results.append(msg) }
                return results
            }
        }
    }

    private struct FakeStreamingTool: AIToolProgressReporting {
        let name: String
        let description: String = "fake_stream"
        var parameters: [String : Any] { ["type": "object", "properties": [:]] }
        let response: String

        func execute(arguments _: [String : Any]) async throws -> String {
            response
        }

        func execute(arguments _: [String : Any], onProgress: @Sendable @escaping (String) -> Void) async throws -> String {
            onProgress("chunk")
            return response
        }
    }

    private func makeToolsForVerifyLoopTest() -> [AITool] {
        [
            FakeTool(name: "planner", response: "Plan saved."),
            FakeStreamingTool(name: "run_command", response: "ok"),
            FakeTool(name: "patchset_apply", response: "Applied.")
        ]
    }

    private func makeToolsForAllowlistTest() -> [AITool] {
        [
            FakeTool(name: "planner", response: "Plan saved."),
            FakeStreamingTool(name: "run_command", response: "ok")
        ]
    }

    private func makeVerifyLoopSend(counter: Counter) -> @Sendable (AgentOrchestrator.SendRequest) async throws -> AIServiceResponse {
        { request in
            await counter.incrementSend()

            let hasVerifier = request.messages.contains(where: { $0.role == .system && $0.content.contains("Verifier role") })
            let hasRunCommandTool = request.tools.contains(where: { $0.name == "run_command" })
            if hasVerifier && hasRunCommandTool {
                return AIServiceResponse(
                    content: "verify",
                    toolCalls: [AIToolCall(id: UUID().uuidString, name: "run_command", arguments: ["command": "xcodebuild test"]) ]
                )
            }

            return AIServiceResponse(content: "ok", toolCalls: nil)
        }
    }

    private func makeVerifyLoopExecuteTools(counter: Counter) -> @Sendable (AgentOrchestrator.ToolExecutionRequest) async -> [ChatMessage] {
        { request in
            if request.tools.contains(where: { $0.name == "run_command" }) {
                await counter.incrementVerifyToolExecutions()
            }
            return request.toolCalls.map { call in
                ChatMessage(
                    role: .tool,
                    content: "executed \(call.name)",
                    tool: ChatMessageToolContext(
                        toolName: call.name,
                        toolStatus: .completed,
                        target: ToolInvocationTarget(targetFile: nil, toolCallId: call.id)
                    )
                )
            }
        }
    }

    func testVerifyLoopCapsToolIterations() async throws {
        let orchestrator = AgentOrchestrator()
        let tools = makeToolsForVerifyLoopTest()

        let initialMessages = [ChatMessage(role: .user, content: "do thing")]

        let counter = Counter()
        let send = makeVerifyLoopSend(counter: counter)
        let executeTools = makeVerifyLoopExecuteTools(counter: counter)

        var emitted: [ChatMessage] = []
        let onMessage: @MainActor @Sendable (ChatMessage) -> Void = { msg in
            emitted.append(msg)
        }

        let config = AgentOrchestrator.Configuration(maxVerifyIterations: 2)
        let env = AgentOrchestrator.Environment(
            allTools: tools,
            send: send,
            executeTools: executeTools,
            onMessage: onMessage
        )
        _ = try await orchestrator.run(
            initialMessages: initialMessages,
            environment: env,
            config: config
        )

        let verifyToolExecutions = await counter.verifyToolExecutions
        let sendCount = await counter.sendCount

        XCTAssertEqual(verifyToolExecutions, 2)
        XCTAssertGreaterThan(sendCount, 0)
        XCTAssertTrue(emitted.count >= 2)
    }

    func testVerifyAllowlistBlocksNonAllowlistedCommand() async throws {
        let orchestrator = AgentOrchestrator()
        let tools = makeToolsForAllowlistTest()

        let initialMessages = [ChatMessage(role: .user, content: "do thing")]
        let send = makeAllowlistSend()
        let executeTools = makeAllowlistExecuteTools()

        var emitted: [ChatMessage] = []
        let onMessage: @MainActor @Sendable (ChatMessage) -> Void = { msg in
            emitted.append(msg)
        }

        let config = AgentOrchestrator.Configuration(maxVerifyIterations: 1, verifyAllowedCommandPrefixes: ["xcodebuild "])
        let env = AgentOrchestrator.Environment(
            allTools: tools,
            send: send,
            executeTools: executeTools,
            onMessage: onMessage
        )
        _ = try await orchestrator.run(
            initialMessages: initialMessages,
            environment: env,
            config: config
        )

        XCTAssertTrue(emitted.contains(where: { $0.role == .tool && $0.content.lowercased().contains("not allowlisted") }))
    }
}
