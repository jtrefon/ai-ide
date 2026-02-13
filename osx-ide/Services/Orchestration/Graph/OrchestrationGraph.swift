import Foundation

protocol OrchestrationNode: Sendable {
    var id: String { get }
    func run(state: OrchestrationState) async throws -> OrchestrationState
}

struct OrchestrationGraph: Sendable {
    let entryNodeId: String
    private let nodesById: [String: any OrchestrationNode]

    init(entryNodeId: String, nodes: [any OrchestrationNode]) {
        self.entryNodeId = entryNodeId
        var dict: [String: any OrchestrationNode] = [:]
        for node in nodes {
            dict[node.id] = node
        }
        self.nodesById = dict
    }

    func node(id: String) -> (any OrchestrationNode)? {
        nodesById[id]
    }
}
