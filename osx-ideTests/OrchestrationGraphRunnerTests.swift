import XCTest

@testable import osx_ide

@MainActor
final class OrchestrationGraphRunnerTests: XCTestCase {
    private actor LogBox {
        private var lines: [String] = []

        func append(_ line: String) {
            lines.append(line)
        }

        func snapshot() -> [String] {
            lines
        }
    }

    private struct NoopTool: AITool {
        let name: String = "noop"
        let description: String = "noop"

        var parameters: [String: Any] {
            ["type": "object", "properties": [:]]
        }

        func execute(arguments _: ToolArguments) async throws -> String {
            "ok"
        }
    }

    @MainActor
    private struct AppendToLogNode: OrchestrationNode {
        let id: String
        let output: String
        let nextId: String?
        let log: LogBox

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            await log.append(output)
            return OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                transition: nextId.map { .next($0) } ?? .end
            )
        }
    }

    func testRunnerExecutesNodesDeterministicallyInOrder() async throws {
        let log = LogBox()

        let graph = OrchestrationGraph(
            entryNodeId: "a",
            nodes: [
                AppendToLogNode(id: "a", output: "A", nextId: "b", log: log),
                AppendToLogNode(id: "b", output: "B", nextId: "c", log: log),
                AppendToLogNode(id: "c", output: "C", nextId: nil, log: log)
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 10)
        let state = try await runner.run(initialState: OrchestrationState(
            request: makeSendRequest(),
            transition: .next("a")
        ))

        _ = state
        let snapshot = await log.snapshot()
        XCTAssertEqual(snapshot, ["A", "B", "C"])
    }

    func testRunnerThrowsWhenExceedingMaxTransitions() async {
        let graph = OrchestrationGraph(
            entryNodeId: "loop",
            nodes: [
                LoopNode(id: "loop")
            ]
        )

        let runner = OrchestrationGraphRunner(graph: graph, maxTransitions: 3)

        do {
            _ = try await runner.run(initialState: OrchestrationState(
                request: makeSendRequest(),
                transition: .next("loop")
            ))
            XCTFail("Expected runner to throw")
        } catch {
            XCTAssertTrue(String(describing: error).localizedCaseInsensitiveContains("maxTransitions"))
        }
    }

    @MainActor
    private struct LoopNode: OrchestrationNode {
        let id: String

        func run(state: OrchestrationState) async throws -> OrchestrationState {
            OrchestrationState(
                request: state.request,
                response: state.response,
                lastToolResults: state.lastToolResults,
                transition: .next(id)
            )
        }
    }

    private func makeSendRequest() -> SendRequest {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        return SendRequest(
            userInput: "Hello",
            explicitContext: nil,
            mode: .chat,
            projectRoot: projectRoot,
            conversationId: UUID().uuidString,
            runId: UUID().uuidString,
            availableTools: [NoopTool()],
            cancelledToolCallIds: { [] },
            qaReviewEnabled: false,
            draftAssistantMessageId: nil
        )
    }
}
