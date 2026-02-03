import Foundation

struct LocalModelFileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func modelsRootDirectory() -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return appSupport
            .appendingPathComponent("osx-ide", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    func modelDirectory(modelId: String, quantization: LocalModelQuantization) -> URL {
        modelsRootDirectory()
            .appendingPathComponent(modelId, isDirectory: true)
            .appendingPathComponent(quantization.rawValue, isDirectory: true)
    }

    func ensureModelDirectoryExists(modelId: String, quantization: LocalModelQuantization) throws -> URL {
        let dir = modelDirectory(modelId: modelId, quantization: quantization)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func isModelDownloaded(modelId: String, quantization: LocalModelQuantization, expectedFiles: [String]) -> Bool {
        let dir = modelDirectory(modelId: modelId, quantization: quantization)
        for file in expectedFiles {
            let url = dir.appendingPathComponent(file)
            if !fileManager.fileExists(atPath: url.path) {
                return false
            }
        }
        return true
    }
}
