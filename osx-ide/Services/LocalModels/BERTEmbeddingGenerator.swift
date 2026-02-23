import CoreML
import Foundation

/// BERT-style embedding generator that works with tokenized inputs
/// Supports models like BGE, Nomic Embed, and other sentence transformers
public final class BERTEmbeddingGenerator: MemoryEmbeddingGenerating, @unchecked Sendable {
    public let modelIdentifier: String
    public let dimensions: Int
    public let usesNPU: Bool
    
    private let model: MLModel
    private let tokenizer: any Sendable & _TokenizerProtocol
    private let sequenceLength: Int
    
    public enum BERTEmbeddingError: Error, LocalizedError {
        case modelNotFound
        case modelLoadFailed(Error)
        case invalidInputShape
        case invalidOutput
        case tokenizerNotAvailable
        
        public var errorDescription: String? {
            switch self {
            case .modelNotFound:
                return "Embedding model not found"
            case .modelLoadFailed(let error):
                return "Failed to load embedding model: \(error.localizedDescription)"
            case .invalidInputShape:
                return "Invalid input shape for embedding model"
            case .invalidOutput:
                return "Invalid output from embedding model"
            case .tokenizerNotAvailable:
                return "Tokenizer not available for this model"
            }
        }
    }
    
    private init(
        model: MLModel,
        modelIdentifier: String,
        dimensions: Int,
        tokenizer: any Sendable & _TokenizerProtocol,
        sequenceLength: Int,
        usesNPU: Bool
    ) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.dimensions = dimensions
        self.tokenizer = tokenizer
        self.sequenceLength = sequenceLength
        self.usesNPU = usesNPU
    }
    
    /// Load a bundled CoreML embedding model
    public static func loadBundledModel(
        modelName: String,
        dimensions: Int,
        sequenceLength: Int = 128
    ) async -> BERTEmbeddingGenerator? {
        // Xcode copies resources to the app bundle root (flattened structure)
        // Try multiple locations in order of preference
        let searchPaths = [
            // Try direct bundle resource (Xcode copies to bundle root)
            Bundle.main.resourceURL,
            // Try app bundle
            Bundle.main.bundleURL,
            // Try Resources subdirectory (for development builds)
            Bundle.main.bundleURL.appendingPathComponent("Resources"),
            // Try EmbeddingModels subdirectory
            Bundle.main.bundleURL.appendingPathComponent("Resources/EmbeddingModels"),
        ]
        
        for basePath in searchPaths {
            guard let base = basePath else { continue }
            let modelURL = base.appendingPathComponent("\(modelName).mlmodelc")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                return await loadModelFromURL(modelURL, modelName: modelName, dimensions: dimensions, sequenceLength: sequenceLength)
            }
        }
        
        // Fallback: try Bundle.main.url forResource
        if let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return await loadModelFromURL(modelURL, modelName: modelName, dimensions: dimensions, sequenceLength: sequenceLength)
        }
        
        return nil
    }
    
    /// Load model from a specific URL
    public static func loadModelFromURL(
        _ modelURL: URL,
        modelName: String,
        dimensions: Int,
        sequenceLength: Int = 128
    ) async -> BERTEmbeddingGenerator? {
        await Task.detached(priority: .userInitiated) {
            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine
                
                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                
                // Our models are converted as mlprogram format which supports Neural Engine
                // With .cpuAndNeuralEngine compute units, CoreML will use NPU when available
                let usesNPU = true
                
                // Use simple tokenizer (character-level fallback)
                // For production, you'd want to bundle vocab.txt files
                let tokenizer = SimpleTokenizer(maxLength: sequenceLength)
                
                return BERTEmbeddingGenerator(
                    model: model,
                    modelIdentifier: "bert_\(modelName)",
                    dimensions: dimensions,
                    tokenizer: tokenizer,
                    sequenceLength: sequenceLength,
                    usesNPU: usesNPU
                )
            } catch {
                print("[BERTEmbeddingGenerator] Failed to load model \(modelName): \(error)")
                return nil
            }
        }.value
    }
    
    public func generateEmbedding(for text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // Tokenize
        let (inputIds, attentionMask, tokenTypeIds) = tokenizer.tokenize(trimmed)
        
        // Create MLMultiArray inputs
        guard let inputIdsArray = try? createMultiArray(from: inputIds),
              let attentionMaskArray = try? createMultiArray(from: attentionMask),
              let tokenTypeIdsArray = try? createMultiArray(from: tokenTypeIds)
        else {
            throw BERTEmbeddingError.invalidInputShape
        }
        
        // Create feature provider
        let provider = try MultiArrayFeatureProvider(
            inputIds: inputIdsArray,
            attentionMask: attentionMaskArray,
            tokenTypeIds: tokenTypeIdsArray
        )
        
        // Run prediction
        let output = try await model.prediction(from: provider)
        
        // Extract embedding from output
        return try extractEmbedding(from: output)
    }
    
    private func createMultiArray(from values: [Int]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (index, value) in values.enumerated() {
            pointer[index] = Int32(value)
        }
        return array
    }
    
    private func extractEmbedding(from output: MLFeatureProvider) throws -> [Float] {
        // Find the output feature (usually last_hidden_state or similar)
        guard let outputFeature = output.featureNames.first,
              let multiArray = output.featureValue(for: outputFeature)?.multiArrayValue
        else {
            throw BERTEmbeddingError.invalidOutput
        }
        
        // BERT models output shape: [1, sequence_length, hidden_size]
        // We need to get the [CLS] token embedding (first token)
        let hiddenSize = multiArray.shape[2].intValue
        
        var embedding = Array(repeating: Float(0), count: hiddenSize)
        
        // Extract [CLS] token embedding (position 0)
        for i in 0..<hiddenSize {
            let index = [0, 0, i] as [NSNumber]
            embedding[i] = multiArray[index].floatValue
        }
        
        // Normalize
        let sumSquares = embedding.reduce(Float(0)) { $0 + $1 * $1 }
        if sumSquares > 0 {
            let norm = sqrt(sumSquares)
            embedding = embedding.map { $0 / norm }
        }
        
        return embedding
    }
}

/// Protocol for tokenizers (internal)
internal protocol _TokenizerProtocol {
    func tokenize(_ text: String) -> (inputIds: [Int], attentionMask: [Int], tokenTypeIds: [Int])
}

extension SimpleTokenizer: _TokenizerProtocol {}
extension BERTTokenizer: _TokenizerProtocol {}

/// Feature provider for multi-array inputs
private final class MultiArrayFeatureProvider: NSObject, MLFeatureProvider {
    let inputIds: MLMultiArray
    let attentionMask: MLMultiArray
    let tokenTypeIds: MLMultiArray
    
    var featureNames: Set<String> {
        ["input_ids", "attention_mask", "token_type_ids"]
    }
    
    init(inputIds: MLMultiArray, attentionMask: MLMultiArray, tokenTypeIds: MLMultiArray) throws {
        self.inputIds = inputIds
        self.attentionMask = attentionMask
        self.tokenTypeIds = tokenTypeIds
        super.init()
    }
    
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "input_ids":
            return MLFeatureValue(multiArray: inputIds)
        case "attention_mask":
            return MLFeatureValue(multiArray: attentionMask)
        case "token_type_ids":
            return MLFeatureValue(multiArray: tokenTypeIds)
        default:
            return nil
        }
    }
}

// MARK: - Factory for creating BERT embedding generators

public enum BERTEmbeddingGeneratorFactory {
    /// Available bundled models
    public static let bundledModels: [(name: String, dimensions: Int, displayName: String)] = [
        ("bge-small-en-v1.5", 512, "BGE Small English v1.5"),
        ("bge-base-en-v1.5", 768, "BGE Base English v1.5"),
        ("bge-large-en-v1.5", 1024, "BGE Large English v1.5"),
        ("nomic-embed-text-v1.5", 768, "Nomic Embed Text v1.5"),
    ]
    
    /// Load the first available bundled model
    public static func loadFirstAvailable() async -> BERTEmbeddingGenerator? {
        for (name, dimensions, _) in bundledModels {
            if let generator = await BERTEmbeddingGenerator.loadBundledModel(
                modelName: name,
                dimensions: dimensions
            ) {
                print("[BERTEmbeddingGenerator] Loaded bundled model: \(name)")
                return generator
            }
        }
        print("[BERTEmbeddingGenerator] No bundled models found")
        return nil
    }
    
    /// Load a specific bundled model by name
    public static func load(modelName: String) async -> BERTEmbeddingGenerator? {
        guard let modelInfo = bundledModels.first(where: { $0.name == modelName }) else {
            return nil
        }
        return await BERTEmbeddingGenerator.loadBundledModel(
            modelName: modelInfo.name,
            dimensions: modelInfo.dimensions
        )
    }
}
