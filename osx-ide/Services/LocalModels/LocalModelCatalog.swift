import Foundation
@preconcurrency import MLXLMCommon

enum LocalModelCatalog {
    static func allModels() -> [LocalModelDefinition] {
        [
            gemma_4_e4b_it_4bit(),
            qwen3_4B_Instruct_2507(),
            qwen3_5_4B_MLX_4bit(),
            granite_4_0_h_micro_4bit()
        ]
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

    private static func qwen3_4B_Instruct_2507() -> LocalModelDefinition {
        // MLX-optimized 4-bit quantized version from mlx-community
        // Uses ~2GB memory instead of ~8GB for full precision
        let base = "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve/50d4277/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: makeURL(base: base, fileName: fileName))
        }

        return LocalModelDefinition(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit@50d4277",
            displayName: "Qwen3-4B-Instruct-2507-4bit (50d4277)",
            artifacts: [
                artifact("config.json"),
                artifact("generation_config.json"),
                artifact("tokenizer.json"),
                artifact("tokenizer_config.json"),
                artifact("merges.txt"),
                artifact("vocab.json"),
                artifact("model.safetensors"),
                artifact("model.safetensors.index.json"),
                artifact("chat_template.jinja"),
                artifact("special_tokens_map.json"),
                artifact("added_tokens.json")
            ],
            defaultContextLength: 8192,
            toolCallFormat: .json
        )
    }

    private static func granite_4_0_h_micro_4bit() -> LocalModelDefinition {
        let base = "https://huggingface.co/mlx-community/granite-4.0-h-micro-4bit/resolve/0a29e17/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: makeURL(base: base, fileName: fileName))
        }

        return LocalModelDefinition(
            id: "mlx-community/granite-4.0-h-micro-4bit@0a29e17",
            displayName: "Granite-4.0-H-Micro-4bit (0a29e17)",
            artifacts: [
                artifact("model.safetensors"),
                artifact("model.safetensors.index.json"),
                artifact("config.json"),
                artifact("generation_config.json"),
                artifact("chat_template.jinja"),
                artifact("tokenizer.json"),
                artifact("tokenizer_config.json"),
                artifact("special_tokens_map.json"),
                artifact("merges.txt"),
                artifact("vocab.json")
            ],
            defaultContextLength: 4096,
            toolCallFormat: .json
        )
    }

    private static func qwen3_5_4B_MLX_4bit() -> LocalModelDefinition {
        let base = "https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit/resolve/main/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: makeURL(base: base, fileName: fileName))
        }

        return LocalModelDefinition(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit@main",
            displayName: "Qwen3.5-4B-MLX-4bit (experimental)",
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
            defaultContextLength: 8192,
            toolCallFormat: .json
        )
    }

    private static func gemma_4_e4b_it_4bit() -> LocalModelDefinition {
        let base = "https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit/resolve/62b0e4e/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: makeURL(base: base, fileName: fileName))
        }

        return LocalModelDefinition(
            id: "mlx-community/gemma-4-e4b-it-4bit@62b0e4e",
            displayName: "Gemma-4-E4B-IT-4bit (62b0e4e)",
            artifacts: [
                artifact("chat_template.jinja"),
                artifact("config.json"),
                artifact("generation_config.json"),
                artifact("model.safetensors"),
                artifact("model.safetensors.index.json"),
                artifact("processor_config.json"),
                artifact("tokenizer.json"),
                artifact("tokenizer_config.json")
            ],
            defaultContextLength: 8192,
            toolCallFormat: .gemma
        )
    }
}
