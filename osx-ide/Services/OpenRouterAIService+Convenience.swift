import Foundation

extension OpenRouterAIService {
    func explainCode(_ code: String) async throws -> String {
        let prompt = "Explain the following code in clear, concise terms:\n\n\(code)"
        let response = try await performChat(
            prompt: prompt,
            context: (nil as String?),
            tools: (nil as [AITool]?),
            mode: (nil as AIMode?),
            projectRoot: (nil as URL?)
        )
        return response.content ?? ""
    }

    func refactorCode(_ code: String, instructions: String) async throws -> String {
        let prompt = "Refactor this code using the following instructions:\n\(instructions)\n\nCode:\n\(code)"
        let response = try await performChat(
            prompt: prompt,
            context: (nil as String?),
            tools: (nil as [AITool]?),
            mode: (nil as AIMode?),
            projectRoot: (nil as URL?)
        )
        return response.content ?? ""
    }

    func generateCode(_ prompt: String) async throws -> String {
        let message = "Generate code for the following request:\n\(prompt)"
        let response = try await performChat(
            prompt: message,
            context: (nil as String?),
            tools: (nil as [AITool]?),
            mode: (nil as AIMode?),
            projectRoot: (nil as URL?)
        )
        return response.content ?? ""
    }

    func fixCode(_ code: String, error: String) async throws -> String {
        let prompt = "Fix this code. Error message:\n\(error)\n\nCode:\n\(code)"
        let response = try await performChat(
            prompt: prompt,
            context: (nil as String?),
            tools: (nil as [AITool]?),
            mode: (nil as AIMode?),
            projectRoot: (nil as URL?)
        )
        return response.content ?? ""
    }
}
