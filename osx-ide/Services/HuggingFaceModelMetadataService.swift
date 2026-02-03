import Foundation

actor HuggingFaceModelMetadataService {
    struct ModelFile: Decodable {
        let rfilename: String
        let size: Int?
    }

    struct ModelResponse: Decodable {
        let siblings: [ModelFile]?
    }

    enum MetadataError: LocalizedError {
        case badHTTPStatus(Int)

        var errorDescription: String? {
            switch self {
            case .badHTTPStatus(let status):
                return "Hugging Face API returned HTTP \(status)"
            }
        }
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchTotalSizeBytes(repository: String, files: [String]) async throws -> Int {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repository)") else {
            return 0
        }

        let (data, response) = try await urlSession.data(from: url)
        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw MetadataError.badHTTPStatus(http.statusCode)
            }
        }

        let decoded = try JSONDecoder().decode(ModelResponse.self, from: data)
        let siblings = decoded.siblings ?? []

        var sizeByFilename: [String: Int] = [:]
        for file in siblings {
            guard let size = file.size else { continue }
            sizeByFilename[file.rfilename] = size
        }

        return files.reduce(0) { partial, filename in
            partial + (sizeByFilename[filename] ?? 0)
        }
    }
}
