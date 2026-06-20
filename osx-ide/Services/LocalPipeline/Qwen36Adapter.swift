import Foundation

/// Adapter for Qwen3.6 4B 4bit (MLX).
/// When the upstream MLX community model is published, this adapter provides
/// model-specific configuration — context length, tool call format, reasoning
/// support, and chat template overrides.
///
/// Current target: Qwen3-4B (2507), the closest available 4B model from
/// the Qwen3.x family with MLX 4bit support. Swap to Qwen3.6 4B once
/// mlx-community publishes it.
struct Qwen36Adapter: LocalModelAdapter {
    let contextLength: Int = 8192
    let toolCallFormat: LocalModelToolCallFormat = .json
    let supportsReasoning: Bool = true
    let supportsTurboQuant: Bool = true

    func tokenize(_ text: String) -> [Int] {
        []
    }

    func decode(_ tokenIds: [Int]) -> String {
        ""
    }

    func formatPrompt(
        messages: [ChatMessage], tools: [AITool]?, mode: AIMode
    ) -> String? {
        nil
    }

    func additionalContext(enableThinking: Bool) -> [String: any Sendable] {
        ["enable_thinking": enableThinking]
    }
}
