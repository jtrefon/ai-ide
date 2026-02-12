import Foundation

enum LocalModelFileStore {
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
