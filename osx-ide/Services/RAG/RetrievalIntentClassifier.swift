import Foundation

public struct RetrievalIntentClassifier: Sendable {
    public init() {}

    public func classify(userInput: String) -> RetrievalIntent {
        let normalized = userInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return .other
        }

        if containsAny(
            of: ["bug", "fix", "error", "crash", "failing", "regression", "broken", "resolve", "doesn't work", "memory leak", "patch", "vulnerability"],
            in: normalized
        ) {
            return .bugfix
        }

        if containsAny(
            of: ["refactor", "cleanup", "simplify", "extract", "restructure", "reorganize", "organization"],
            in: normalized
        ) {
            return .refactor
        }

        if containsAny(
            of: ["explain", "why", "how does", "what does", "describe", "how is", "what's the purpose", "understand"],
            in: normalized
        ) {
            return .explanation
        }

        if containsAny(
            of: ["test", "coverage", "xctest", "unit test", "regression test", "test case", "test suite", "integration test"],
            in: normalized
        ) {
            return .tests
        }

        if containsAny(
            of: ["debt", "unused", "dead code", "duplicate", "cleanup", "clean up", "delete", "remove", "eliminate"],
            in: normalized
        ) {
            return .cleanup
        }

        if containsAny(
            of: ["feature", "implement", "add", "support", "introduce", "create", "build", "develop"],
            in: normalized
        ) {
            return .feature
        }

        if containsAny(of: ["architecture"], in: normalized) {
            return .explanation
        }

        return .other
    }

    private func containsAny(of needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
