import Foundation
@preconcurrency import MLXLMCommon

enum LocalModelCatalog {
    static let defaultModel = qwen3_5_4B_MLX_4bit()

    static func allModels() -> [LocalModelDefinition] {
        [defaultModel]
    }

    static func model(id: String) -> LocalModelDefinition? {
        allModels().first(where: { $0.id == id })
    }

    private static func makeURL(base: String, fileName: String) -> URL {
        let fullString = base + fileName
        if let url = URL(string: fullString) {
            return url
        }
        if let escapedString = fullString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: escapedString) {
            return url
        }
        return URL(string: "https://huggingface.co")!
    }

    private static func qwen3_5_4B_MLX_4bit() -> LocalModelDefinition {
        let base = "https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit/resolve/main/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: makeURL(base: base, fileName: fileName))
        }

        return LocalModelDefinition(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit@main",
            displayName: "Qwen3.5-4B-MLX-4bit",
            artifacts: [
                artifact("chat_template.jinja"),
                artifact("config.json"),
                artifact("model.safetensors"),
                artifact("model.safetensors.index.json"),
                artifact("preprocessor_config.json"),
                artifact("processor_config.json"),
                artifact("tokenizer.json"),
                artifact("tokenizer_config.json"),
                artifact("video_preprocessor_config.json"),
                artifact("vocab.json")
            ],
            defaultContextLength: 65536,
            toolCallFormat: .json
        )
    }
}
