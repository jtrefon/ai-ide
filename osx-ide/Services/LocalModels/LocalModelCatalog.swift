import Foundation

enum LocalModelCatalog {
    static func allModels() -> [LocalModelDefinition] {
        [
            qwen3_4B_Instruct_2507(),
            granite_4_0_h_micro_4bit()
        ]
    }

    static func model(id: String) -> LocalModelDefinition? {
        allModels().first(where: { $0.id == id })
    }

    private static func qwen3_4B_Instruct_2507() -> LocalModelDefinition {
        // MLX-optimized 4-bit quantized version from mlx-community
        // Uses ~2GB memory instead of ~8GB for full precision
        let base = "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve/50d4277/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: URL(string: base + fileName)!)
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
            defaultContextLength: 32768
        )
    }

    private static func granite_4_0_h_micro_4bit() -> LocalModelDefinition {
        let base = "https://huggingface.co/mlx-community/granite-4.0-h-micro-4bit/resolve/0a29e17/"

        func artifact(_ fileName: String) -> LocalModelArtifact {
            LocalModelArtifact(fileName: fileName, url: URL(string: base + fileName)!)
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
            defaultContextLength: 4096
        )
    }
}
