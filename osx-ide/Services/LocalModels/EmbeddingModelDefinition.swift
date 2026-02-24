import Foundation

/// Format of the embedding model
public enum EmbeddingModelFormat: String, Codable, Sendable {
    case coreml = "coreml"
    case onnx = "onnx"
    case pytorch = "pytorch"
}

public struct EmbeddingModelDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let dimensions: Int
    public let huggingFaceRepo: String
    public let fileName: String
    public let downloadURL: URL
    /// Size in bytes (approximate, for display purposes)
    public let sizeBytes: Int64
    /// Model format (CoreML, ONNX, PyTorch)
    public let modelFormat: EmbeddingModelFormat
    /// Instructions for converting to CoreML (if applicable)
    public let conversionInstructions: String?

    public var idField: String { id }

    /// Returns human-readable size string
    public var sizeDisplayString: String {
        let mb = Double(sizeBytes) / (1024 * 1024)
        if mb < 1 {
            return String(format: "%.0f KB", Double(sizeBytes) / 1024)
        }
        return String(format: "%.0f MB", mb)
    }

    public init(
        id: String,
        name: String,
        dimensions: Int,
        huggingFaceRepo: String,
        fileName: String,
        downloadURL: URL,
        sizeBytes: Int64 = 0,
        modelFormat: EmbeddingModelFormat = .coreml,
        conversionInstructions: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dimensions = dimensions
        self.huggingFaceRepo = huggingFaceRepo
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.modelFormat = modelFormat
        self.conversionInstructions = conversionInstructions
    }
}
