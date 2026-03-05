import Foundation

public struct RetrievalIntentClassifier: Sendable {
    public init() {}

    public func classify(userInput: String) -> RetrievalIntent {
        let normalized = userInput.lowercased()

        if containsAny(of: ["bug", "fix", "error", "crash", "failing", "regression"], in: normalized) {
            return .bugfix
        }

        if containsAny(of: ["feature", "implement", "add", "support", "introduce"], in: normalized) {
            return .feature
        }

        if containsAny(of: ["refactor", "cleanup", "simplify", "extract", "restructure"], in: normalized) {
            return .refactor
        }

        if containsAny(of: ["explain", "why", "how does", "what does", "describe"], in: normalized) {
            return .explanation
        }

        if containsAny(of: ["test", "coverage", "xctest", "unit test", "regression test"], in: normalized) {
            return .tests
        }

        if containsAny(of: ["debt", "unused", "dead code", "duplicate", "cleanup"], in: normalized) {
            return .cleanup
        }

        return .other
    }

    private func containsAny(of needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
