import Foundation

public actor EmbeddingModelDownloader {
    public struct Progress: Sendable {
        public let fractionCompleted: Double
        public let currentFileName: String?

        public init(fractionCompleted: Double, currentFileName: String?) {
            self.fractionCompleted = fractionCompleted
            self.currentFileName = currentFileName
        }
    }

    public enum DownloadError: LocalizedError {
        case invalidResponse
        case httpError(status: Int)
        case storageError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid download response."
            case .httpError(let status): return "Download failed with status code \(status)."
            case .storageError(let msg): return "Storage error: \(msg)"
            }
        }
    }

    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func download(
        model: EmbeddingModelDefinition,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        let modelsRoot = try LocalModelFileStore.modelsRootDirectory()
        let destination =
            modelsRoot
            .appendingPathComponent("embeddings", isDirectory: true)
            .appendingPathComponent(model.id, isDirectory: true)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let fileURL = destination.appendingPathComponent(model.fileName)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            onProgress(Progress(fractionCompleted: 1.0, currentFileName: model.fileName))
            return fileURL
        }

        onProgress(Progress(fractionCompleted: 0.0, currentFileName: model.fileName))

        let (tempURL, response) = try await urlSession.download(from: model.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.httpError(status: httpResponse.statusCode)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        onProgress(Progress(fractionCompleted: 1.0, currentFileName: model.fileName))
        return fileURL
    }
}
