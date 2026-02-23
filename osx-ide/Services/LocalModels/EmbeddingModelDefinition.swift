import Foundation

public struct EmbeddingModelDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let dimensions: Int
    public let huggingFaceRepo: String
    public let fileName: String
    public let downloadURL: URL

    public var idField: String { id }

    public init(
        id: String, name: String, dimensions: Int, huggingFaceRepo: String, fileName: String,
        downloadURL: URL
    ) {
        self.id = id
        self.name = name
        self.dimensions = dimensions
        self.huggingFaceRepo = huggingFaceRepo
        self.fileName = fileName
        self.downloadURL = downloadURL
    }
}
