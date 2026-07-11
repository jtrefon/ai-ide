import Foundation

/// Pure-function reducer for `PipelineState`.
///
/// This is the "Reducer" in a Redux-like architecture:
///   - No side effects, no I/O, no async.
///   - Given the current state and an event, returns the new state.
///   - Fully deterministic and testable with simple assertions.
///
/// SRP: This is the ONLY place where `PipelineState` is mutated.
/// Every stage delegates state updates here rather than touching state directly.
public enum PipelineReducer {

    /// Apply an event to the current state, returning the new state.
    /// - Parameters:
    ///   - state: The current pipeline state (immutable input).
    ///   - event: The event to reduce.
    /// - Returns: The new pipeline state.
    public static func reduce(state: PipelineState, event: PipelineEvent) -> PipelineState {
        var next = state

        switch event {
        case .segment(let segment):
            reduceSegment(&next, segment)

        case .toolCallOpened(let id, let tool):
            next.toolCallDrafts[id] = RawToolCallDraft(id: id, tool: tool)

        case .toolCallArguments(let id, let fragment):
            next.toolCallDrafts[id]?.accumulatedArguments += fragment

        case .toolCallCompleted(let id, let tool, let arguments):
            next.toolCallDrafts.removeValue(forKey: id)
            next.completedToolCalls.append(
                CompletedToolCall(id: id, tool: tool, arguments: arguments)
            )

        case .toolCallFailed(let id, let tool, let rawArguments, let error):
            next.toolCallDrafts.removeValue(forKey: id)
            next.malformedToolCalls.append(
                MalformedToolCallRecord(id: id, tool: tool, rawArguments: rawArguments, error: error)
            )

        case .status(let provider, let info):
            next.status[provider] = info

        case .finished:
            next.isComplete = true

        case .error(let pipelineError):
            next.error = pipelineError
            next.isComplete = true
        }

        return next
    }

    // MARK: - Segment Reduction

    private static func reduceSegment(_ state: inout PipelineState, _ segment: Segment) {
        switch segment.kind {
        case .userVisible:
            state.content.append(segment.text)
        case .reasoning:
            state.reasoning = (state.reasoning ?? "") + segment.text
        case .toolCallMarkup:
            // Tool-call markup is suppressed from user-visible content
            // by the stage that classifies it; nothing to do here. If a
            // tool-call-markup segment arrives at the reducer, it means
            // a stage chose not to parse it — we still suppress display.
            break
        case .status:
            break
        case .error:
            state.error = PipelineError(
                code: .stageFailure,
                message: segment.text,
                sourceStage: segment.source
            )
            state.isComplete = true
        }
    }
}
