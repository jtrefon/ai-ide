import Foundation

enum LocalModelFileStore {
    struct ModelConfig: Codable {
        let maxPositionEmbeddings: Int?
        let maxSequenceLength: Int?
        let modelType: String?

        enum CodingKeys: String, CodingKey {
            case maxPositionEmbeddings = "max_position_embeddings"
            case maxSequenceLength = "max_sequence_length"
            case modelType = "model_type"
        }

        var contextLength: Int? {
            maxPositionEmbeddings ?? maxSequenceLength
        }
    }

    static func modelsRootDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let root = appSupport
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

    static func isModelInstalled(_ model: LocalModelDefinition) -> Bool {
        for artifact in model.artifacts {
            guard let url = try? artifactURL(modelId: model.id, fileName: artifact.fileName) else { return false }
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
              let config = try? JSONDecoder().decode(ModelConfig.self, from: data) else {
            return nil
        }
        return config
    }

    static func contextLength(for model: LocalModelDefinition) -> Int {
        // Try to load from config.json first
        if let config = loadModelConfig(modelId: model.id),
           let contextLength = config.contextLength {
            return contextLength
        }
        // Fall back to definition default
        return model.defaultContextLength
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
