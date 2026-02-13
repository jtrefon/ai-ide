import Foundation

actor LocalModelDownloader {
    struct Progress: Sendable {
        let completedArtifacts: Int
        let totalArtifacts: Int
        let currentFileName: String?

        var fractionCompleted: Double {
            guard totalArtifacts > 0 else { return 0 }
            return Double(completedArtifacts) / Double(totalArtifacts)
        }
    }

    enum DownloadError: LocalizedError {
        case invalidResponse
        case httpError(status: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid download response."
            case .httpError(let status):
                return "Download failed with status code \(status)."
            }
        }
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func download(
        model: LocalModelDefinition,
        onProgress: @Sendable (Progress) -> Void
    ) async throws {
        let modelDirectory = try LocalModelFileStore.modelDirectory(modelId: model.id)
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        var completed = 0
        onProgress(Progress(completedArtifacts: completed, totalArtifacts: model.artifacts.count, currentFileName: nil))

        for artifact in model.artifacts {
            let destinationURL = try LocalModelFileStore.artifactURL(modelId: model.id, fileName: artifact.fileName)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                completed += 1
                onProgress(Progress(completedArtifacts: completed, totalArtifacts: model.artifacts.count, currentFileName: artifact.fileName))
                continue
            }

            onProgress(Progress(completedArtifacts: completed, totalArtifacts: model.artifacts.count, currentFileName: artifact.fileName))

            // Use downloadTask for streaming to disk (avoids memory spike)
            // This downloads to a temporary file first, then we move it
            let (localURL, response) = try await urlSession.download(from: artifact.url)
            guard let http = response as? HTTPURLResponse else {
                throw DownloadError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw DownloadError.httpError(status: http.statusCode)
            }

            // Move from temp location to final destination
            // If destination exists (race condition), remove it first
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: localURL, to: destinationURL)

            completed += 1
            onProgress(Progress(completedArtifacts: completed, totalArtifacts: model.artifacts.count, currentFileName: artifact.fileName))
        }
    }
}
