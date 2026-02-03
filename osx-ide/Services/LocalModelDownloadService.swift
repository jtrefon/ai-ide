import Foundation

actor LocalModelDownloadService {
    enum DownloadError: LocalizedError {
        case unknownModel
        case invalidRemoteURL(String)
        case badHTTPStatus(Int)

        var errorDescription: String? {
            switch self {
            case .unknownModel:
                return "Unknown model"
            case .invalidRemoteURL(let file):
                return "Invalid remote URL for file: \(file)"
            case .badHTTPStatus(let status):
                return "Download failed with HTTP status \(status)"
            }
        }
    }

    struct ProgressSnapshot: Sendable {
        let completedFiles: Int
        let totalFiles: Int

        var fractionComplete: Double {
            guard totalFiles > 0 else { return 0 }
            return Double(completedFiles) / Double(totalFiles)
        }
    }

    private let fileStore: LocalModelFileStore
    private let urlSession: URLSession

    init(
        fileStore: LocalModelFileStore = LocalModelFileStore(),
        urlSession: URLSession = .shared
    ) {
        self.fileStore = fileStore
        self.urlSession = urlSession
    }

    func isDownloaded(modelId: String, quantization: LocalModelQuantization) -> Bool {
        guard let item = LocalModelCatalog.item(id: modelId) else { return false }
        return fileStore.isModelDownloaded(
            modelId: modelId,
            quantization: quantization,
            expectedFiles: item.files
        )
    }

    func download(
        modelId: String,
        quantization: LocalModelQuantization,
        onProgress: @Sendable (ProgressSnapshot) -> Void
    ) async throws {
        guard let item = LocalModelCatalog.item(id: modelId) else {
            throw DownloadError.unknownModel
        }

        let outputDirectory = try fileStore.ensureModelDirectoryExists(
            modelId: modelId,
            quantization: quantization
        )

        let total = item.files.count
        var completed = 0
        onProgress(ProgressSnapshot(completedFiles: completed, totalFiles: total))

        for file in item.files {
            guard let remoteURL = item.huggingFaceFileURL(filePath: file) else {
                throw DownloadError.invalidRemoteURL(file)
            }

            var request = URLRequest(url: remoteURL)
            request.httpMethod = "GET"

            let (tempURL, response) = try await urlSession.download(for: request)

            if let http = response as? HTTPURLResponse {
                guard (200...299).contains(http.statusCode) else {
                    throw DownloadError.badHTTPStatus(http.statusCode)
                }
            }

            let destinationURL = outputDirectory.appendingPathComponent(file)

            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            completed += 1
            onProgress(ProgressSnapshot(completedFiles: completed, totalFiles: total))
        }
    }
}
