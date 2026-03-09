import Foundation

public enum LocalModelFileStore {
    struct ModelConfig: Codable {
        let maxPositionEmbeddings: Int?
        let maxSequenceLength: Int?
        let modelType: String?
        let textConfig: TextConfig?

        struct TextConfig: Codable {
            let maxPositionEmbeddings: Int?
            let maxSequenceLength: Int?
            let modelType: String?

            enum CodingKeys: String, CodingKey {
                case maxPositionEmbeddings = "max_position_embeddings"
                case maxSequenceLength = "max_sequence_length"
                case modelType = "model_type"
            }
        }

        enum CodingKeys: String, CodingKey {
            case maxPositionEmbeddings = "max_position_embeddings"
            case maxSequenceLength = "max_sequence_length"
            case modelType = "model_type"
            case textConfig = "text_config"
        }

        var contextLength: Int? {
            maxPositionEmbeddings
                ?? maxSequenceLength
                ?? textConfig?.maxPositionEmbeddings
                ?? textConfig?.maxSequenceLength
        }

        var effectiveModelType: String? {
            modelType ?? textConfig?.modelType
        }
    }

    public static func modelsRootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let root =
            appSupport
            .appendingPathComponent("osx-ide", isDirectory: true)
            .appendingPathComponent("local-models", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func modelDirectory(modelId: String) throws -> URL {
        let sanitized = sanitizeModelId(modelId)
        return try modelsRootDirectory().appendingPathComponent(sanitized, isDirectory: true)
    }

    static func artifactURL(modelId: String, fileName: String) throws -> URL {
        try modelDirectory(modelId: modelId).appendingPathComponent(fileName, isDirectory: false)
    }

    static func runtimeModelDirectory(for model: LocalModelDefinition) throws -> URL {
        let installedDirectory = try modelDirectory(modelId: model.id)
        guard requiresRuntimeCompatibilityDirectory(model: model) else {
            return installedDirectory
        }

        return try prepareRuntimeCompatibilityDirectory(
            sourceDirectory: installedDirectory,
            model: model
        )
    }

    static func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
        for artifact in model.artifacts {
            guard let url = try? artifactURL(modelId: model.id, fileName: artifact.fileName) else {
                return false
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                return false
            }
        }
        return true
    }

    static func deleteModelDirectory(modelId: String) throws {
        let dir = try modelDirectory(modelId: modelId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    static func loadModelConfig(modelId: String) -> ModelConfig? {
        guard let configURL = try? artifactURL(modelId: modelId, fileName: "config.json"),
            FileManager.default.fileExists(atPath: configURL.path),
            let data = try? Data(contentsOf: configURL),
            let config = try? JSONDecoder().decode(ModelConfig.self, from: data)
        else {
            return nil
        }
        return config
    }

    static func contextLength(for model: LocalModelDefinition) -> Int {
        // Try to load from config.json first
        if let config = loadModelConfig(modelId: model.id),
            let contextLength = config.contextLength
        {
            return contextLength
        }
        // Fall back to definition default
        return model.defaultContextLength
    }

    private static func requiresRuntimeCompatibilityDirectory(model: LocalModelDefinition) -> Bool {
        guard let config = loadModelConfig(modelId: model.id) else {
            return false
        }
        return config.effectiveModelType == "qwen3_5"
    }

    private static func prepareRuntimeCompatibilityDirectory(
        sourceDirectory: URL,
        model: LocalModelDefinition
    ) throws -> URL {
        let runtimeDirectory = sourceDirectory.appendingPathComponent("osx-ide-runtime", isDirectory: true)
        let normalizedConfigData = try normalizedRuntimeConfigData(for: model)

        if FileManager.default.fileExists(atPath: runtimeDirectory.path) {
            try FileManager.default.removeItem(at: runtimeDirectory)
        }
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)

        let fileManager = FileManager.default
        let sourceContents = try fileManager.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for sourceItem in sourceContents {
            guard sourceItem.lastPathComponent != runtimeDirectory.lastPathComponent else {
                continue
            }
            guard sourceItem.lastPathComponent != "config.json" else {
                continue
            }

            let destinationItem = runtimeDirectory.appendingPathComponent(sourceItem.lastPathComponent)
            try fileManager.createSymbolicLink(at: destinationItem, withDestinationURL: sourceItem)
        }

        try normalizedConfigData.write(
            to: runtimeDirectory.appendingPathComponent("config.json"),
            options: Data.WritingOptions.atomic
        )
        return runtimeDirectory
    }

    private static func normalizedRuntimeConfigData(for model: LocalModelDefinition) throws -> Data {
        let configURL = try artifactURL(modelId: model.id, fileName: "config.json")
        let configData = try Data(contentsOf: configURL)
        guard var rootObject = try JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            return configData
        }

        guard rootObject["model_type"] as? String == "qwen3_5",
              let textConfig = rootObject["text_config"] as? [String: Any] else {
            return configData
        }

        if rootObject["vocab_size"] == nil,
           let vocabSize = textConfig["vocab_size"] {
            rootObject["vocab_size"] = vocabSize
        }

        return try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitizeModelId(_ modelId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = modelId.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        return String(mapped)
    }
}
