#if false
import Foundation

public enum AIRequestStage: String, Codable, Sendable {
    case warmup
    case initial_response
    case tool_loop
    case delivery_gate
    case final_response
    case qa_tool_output_review
    case qa_quality_review
    case other
}
#endif
