import Foundation
// Hub and Tokenizers removed — these modules are no longer transitive dependencies
// in mlx-swift-lm 3.x. Restore when swift-transformers is added as direct dependency.

actor LocalModelTokenCounter {
    static let shared = LocalModelTokenCounter()

    // Stub — requires swift-transformers dependency (Hub, Tokenizers modules)
    // which was removed in mlx-swift-lm 3.x transitive deps.
    func tokenCount(text: String, modelId: String) async throws -> Int {
        0
    }
}
