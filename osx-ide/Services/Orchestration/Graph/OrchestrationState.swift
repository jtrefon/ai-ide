import Foundation

@MainActor
struct OrchestrationState: Sendable {
    struct Transition: Sendable {
        let nextNodeId: String?

        static func next(_ id: String) -> Transition {
            Transition(nextNodeId: id)
        }

        static let end = Transition(nextNodeId: nil)
    }

    let request: SendRequest

    var response: AIServiceResponse?
    var lastToolResults: [ChatMessage]

    var transition: Transition

    init(
        request: SendRequest,
        response: AIServiceResponse? = nil,
        lastToolResults: [ChatMessage] = [],
        transition: Transition
    ) {
        self.request = request
        self.response = response
        self.lastToolResults = lastToolResults
        self.transition = transition
    }
}
