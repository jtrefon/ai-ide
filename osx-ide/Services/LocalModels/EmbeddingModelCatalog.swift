import Foundation

public enum EmbeddingModelCatalog {
    /// Models that are bundled with the app (in Resources/EmbeddingModels/)
    public static let bundledModels: [EmbeddingModelDefinition] = [
        // BGE Small - Fast, good quality (63 MB)
        EmbeddingModelDefinition(
            id: "bge-small-en-v1.5",
            name: "BAAI BGE Small English v1.5",
            dimensions: 512,
            huggingFaceRepo: "BAAI/bge-small-en-v1.5",
            fileName: "bge-small-en-v1.5.mlmodelc",
            downloadURL: URL(
                string: "https://huggingface.co/BAAI/bge-small-en-v1.5/resolve/main/onnx/model.onnx"
            )!,
            sizeBytes: 63 * 1024 * 1024,  // ~63 MB (CoreML)
            modelFormat: .coreml,
            conversionInstructions: nil  // Already bundled
        ),
        // BGE Base - Better quality (207 MB)
        EmbeddingModelDefinition(
            id: "bge-base-en-v1.5",
            name: "BAAI BGE Base English v1.5",
            dimensions: 768,
            huggingFaceRepo: "BAAI/bge-base-en-v1.5",
            fileName: "bge-base-en-v1.5.mlmodelc",
            downloadURL: URL(
                string: "https://huggingface.co/BAAI/bge-base-en-v1.5/resolve/main/onnx/model.onnx"
            )!,
            sizeBytes: 207 * 1024 * 1024,  // ~207 MB (CoreML)
            modelFormat: .coreml,
            conversionInstructions: nil  // Already bundled
        ),
        // BGE Large - Best quality (637 MB)
        EmbeddingModelDefinition(
            id: "bge-large-en-v1.5",
            name: "BAAI BGE Large English v1.5",
            dimensions: 1024,
            huggingFaceRepo: "BAAI/bge-large-en-v1.5",
            fileName: "bge-large-en-v1.5.mlmodelc",
            downloadURL: URL(
                string: "https://huggingface.co/BAAI/bge-large-en-v1.5/resolve/main/onnx/model.onnx"
            )!,
            sizeBytes: 637 * 1024 * 1024,  // ~637 MB (CoreML)
            modelFormat: .coreml,
            conversionInstructions: nil  // Already bundled
        ),
        // Nomic Embed Text v1.5 - Highly recommended (261 MB)
        EmbeddingModelDefinition(
            id: "nomic-embed-text-v1.5",
            name: "Nomic Embed Text v1.5",
            dimensions: 768,
            huggingFaceRepo: "nomic-ai/nomic-embed-text-v1.5",
            fileName: "nomic-embed-text-v1.5.mlmodelc",
            downloadURL: URL(
                string: "https://huggingface.co/nomic-ai/nomic-embed-text-v1.5/resolve/main/onnx/model.onnx"
            )!,
            sizeBytes: 261 * 1024 * 1024,  // ~261 MB (CoreML)
            modelFormat: .coreml,
            conversionInstructions: nil  // Already bundled
        ),
    ]
    
    /// Models available for download (ONNX format, require conversion)
    public static let downloadableModels: [EmbeddingModelDefinition] = [
        // All-MiniLM-L6-v2 - Lightweight option (conversion failed, available as ONNX only)
        EmbeddingModelDefinition(
            id: "all-minilm-l6-v2",
            name: "Sentence Transformers all-MiniLM-L6-v2 (ONNX)",
            dimensions: 384,
            huggingFaceRepo: "sentence-transformers/all-MiniLM-L6-v2",
            fileName: "model.onnx",
            downloadURL: URL(
                string: "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx"
            )!,
            sizeBytes: 90 * 1024 * 1024,  // ~90 MB
            modelFormat: .onnx,
            conversionInstructions: "Run: python scripts/convert_embedding_to_coreml.py sentence-transformers/all-MiniLM-L6-v2"
        ),
    ]
    
    /// All available models (bundled first, then downloadable)
    public static let availableModels: [EmbeddingModelDefinition] = bundledModels + downloadableModels

    /// Default model - BGE Small for fast startup, good quality
    public static var defaultModel: EmbeddingModelDefinition {
        bundledModels[0]  // bge-small-en-v1.5 - best quality/size balance for bundled
    }
    
    /// Check if a model is bundled with the app
    public static func isBundled(modelId: String) -> Bool {
        bundledModels.contains { $0.id == modelId }
    }
}
