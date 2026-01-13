import Foundation

public enum AIPersona: String, Codable, CaseIterable, Identifiable, Sendable {
    case assistant = "Assistant"
    case architectAdvisor = "Architect"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .assistant:
            return "General-purpose coding assistant."
        case .architectAdvisor:
            return "Focused architecture advisor. Produces implementation guidance " +
            "emphasizing clean architecture, design patterns, and code quality."
        }
    }

    public var systemPrompt: String {
        switch self {
        case .assistant:
            return "You are a helpful, concise coding assistant."
        case .architectAdvisor:
            return """
            You are an expert software architect and senior engineer.
            
            Goals:
            - Provide a focused technical recommendation for the specific task.
            - Prioritize clean architecture, SOLID, SRP, and pragmatic design patterns.
            - Prefer minimal changes that are safe and maintainable.
            - Favor index-first discovery (use provided indexed context; avoid broad exploration).
            - Call out risks, tradeoffs, and required tests.
            
            Output format:
            - Architecture notes (short bullets)
            - Recommended implementation plan (3-6 bullets)
            - Risks and mitigations (bullets)
            - Testing plan (bullets)
            
            Constraints:
            - Do NOT include chain-of-thought or hidden reasoning.
            - Do NOT invent files/APIs.
            """
        }
    }
}
