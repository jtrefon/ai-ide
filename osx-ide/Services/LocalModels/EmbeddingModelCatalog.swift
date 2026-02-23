import Foundation

public enum EmbeddingModelCatalog {
    public static let availableModels: [EmbeddingModelDefinition] = [
        EmbeddingModelDefinition(
            id: "all-minilm-l6-v2",
            name: "Sentence Transformers all-MiniLM-L6-v2",
            dimensions: 384,
            huggingFaceRepo: "sentence-transformers/all-MiniLM-L6-v2",
            fileName: "model.mlmodelc",
            downloadURL: URL(
                string:
                    "https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/coreml/model.mlmodelc.zip"
            )!
        ),
        EmbeddingModelDefinition(
            id: "text-embedding-3-small",
            name: "OpenAI Text Embedding 3 Small (CoreML)",
            dimensions: 1536,
            huggingFaceRepo: "apple/ml-text-embedding-3-small",
            fileName: "text-embedding-3-small.mlmodelc",
            downloadURL: URL(
                string:
                    "https://huggingface.co/apple/ml-text-embedding-3-small/resolve/main/text-embedding-3-small.mlmodelc.zip"
            )!
        ),
    ]

    public static var defaultModel: EmbeddingModelDefinition {
        availableModels[1]
    }
}
