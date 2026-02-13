import Foundation

@MainActor
final class OrchestrationGraphRunner {
    private let graph: OrchestrationGraph
    private let snapshotter: OrchestrationGraphRunSnapshotter

    private let maxTransitions: Int

    init(
        graph: OrchestrationGraph,
        maxTransitions: Int = 64,
        snapshotter: OrchestrationGraphRunSnapshotter = OrchestrationGraphRunSnapshotter()
    ) {
        self.graph = graph
        self.maxTransitions = maxTransitions
        self.snapshotter = snapshotter
    }

    func run(initialState: OrchestrationState) async throws -> OrchestrationState {
        var state = initialState
        var currentNodeId = initialState.transition.nextNodeId ?? graph.entryNodeId
        var transitionCount = 0

        while transitionCount < maxTransitions {
            transitionCount += 1

            guard let node = graph.node(id: currentNodeId) else {
                throw AppError.unknown("OrchestrationGraphRunner: missing node id=\(currentNodeId)")
            }

            state = try await node.run(state: state)

            await snapshotter.appendTransitionSnapshot(
                nodeId: currentNodeId,
                transitionIndex: transitionCount,
                state: state
            )

            guard let nextId = state.transition.nextNodeId else {
                return state
            }

            currentNodeId = nextId
        }

        throw AppError.unknown("OrchestrationGraphRunner: exceeded maxTransitions=\(maxTransitions)")
    }
}
