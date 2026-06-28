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
    /// Note: All bundled CoreML models have fixed input shape of 128 tokens.
    /// To increase sequence length, the models must be re-exported with flexible shapes.
    public static func loadBundledModel(
        modelName: String,
        dimensions: Int,
        sequenceLength: Int = 128
    ) async -> BERTEmbeddingGenerator? {
        let searchPaths: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Resources"),
            Bundle.main.bundleURL.appendingPathComponent("Resources/EmbeddingModels"),
        ]

        for basePath in searchPaths {
            guard let base = basePath else { continue }
            let modelURL = base.appendingPathComponent("\(modelName).mlmodelc")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                return await loadModelFromURL(modelURL, modelName: modelName, dimensions: dimensions, sequenceLength: sequenceLength)
            }
        }

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
        sequenceLength: Int = 512
    ) async -> BERTEmbeddingGenerator? {
        await Task.detached(priority: .userInitiated) {
            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine

                let model = try MLModel(contentsOf: modelURL, configuration: configuration)

                // Verify NPU is actually being used by measuring first inference
                // CoreML with .cpuAndNeuralEngine may silently fall back to CPU
                // if the model has operations not supported on the Neural Engine.
                // We detect this by measuring inference time — NPU should be <50ms,
                // CPU fallback is typically >100ms for these model sizes.
                let testProvider = try MultiArrayFeatureProvider(
                    inputIds: try createTestMultiArray(sequenceLength: sequenceLength),
                    attentionMask: try createTestMultiArray(sequenceLength: sequenceLength),
                    tokenTypeIds: try createTestMultiArray(sequenceLength: sequenceLength)
                )
                let testStart = ContinuousClock.now
                _ = try? await model.prediction(from: testProvider)
                let testMs = Int(testStart.duration(to: ContinuousClock.now).components.seconds * 1000)
                + Int(testStart.duration(to: ContinuousClock.now).components.attoseconds / 1_000_000_000_000_000)
                let usesNPU = testMs < 100
                if !usesNPU {
                    print("[BERTEmbeddingGenerator] WARNING: \(modelName) inference took \(testMs)ms — likely CPU fallback, not NPU")
                }

                // Try to load BERTTokenizer from vocab.txt alongside the model
                let vocabURL = modelURL.deletingLastPathComponent()
                    .appendingPathComponent("\(modelName).vocab.txt")
                let tokenizer: any Sendable & _TokenizerProtocol

                if FileManager.default.fileExists(atPath: vocabURL.path) {
                    do {
                        tokenizer = try BERTTokenizer.load(from: vocabURL)
                        print("[BERTEmbeddingGenerator] Loaded BERTTokenizer from \(vocabURL.path)")
                    } catch {
                        print("[BERTEmbeddingGenerator] Failed to load vocab.txt: \(error), falling back to SimpleTokenizer")
                        tokenizer = SimpleTokenizer(maxLength: sequenceLength)
                    }
                } else {
                    // Also check parent directories for vocab.txt
                    let altVocabURL = modelURL.deletingLastPathComponent()
                        .appendingPathComponent("vocab.txt")
                    if FileManager.default.fileExists(atPath: altVocabURL.path) {
                        do {
                            tokenizer = try BERTTokenizer.load(from: altVocabURL)
                            print("[BERTEmbeddingGenerator] Loaded BERTTokenizer from \(altVocabURL.path)")
                        } catch {
                            print("[BERTEmbeddingGenerator] Failed to load vocab.txt: \(error), falling back to SimpleTokenizer")
                            tokenizer = SimpleTokenizer(maxLength: sequenceLength)
                        }
                    } else {
                        print("[BERTEmbeddingGenerator] No vocab.txt found, using SimpleTokenizer (embedding quality will be reduced)")
                        tokenizer = SimpleTokenizer(maxLength: sequenceLength)
                    }
                }

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

    private static func createTestMultiArray(sequenceLength: Int) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
        let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: sequenceLength)
        for i in 0..<sequenceLength {
            pointer[i] = 0
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
    
    /// Load the first available bundled model that performs well on NPU.
    /// Models are tried smallest-first. After loading, a quick benchmark is run.
    /// If the benchmark shows the model is running on CPU fallback (>100ms per embedding),
    /// the model is rejected and the next smaller one is tried.
    public static func loadFirstAvailable() async -> BERTEmbeddingGenerator? {
        for (name, dimensions, displayName) in bundledModels {
            guard let generator = await BERTEmbeddingGenerator.loadBundledModel(
                modelName: name,
                dimensions: dimensions
            ) else {
                continue
            }

            // Quick benchmark: if embedding takes >100ms, model is likely on CPU fallback
            let benchmarkText = "func test() -> Int { return 42 }"
            let benchStart = ContinuousClock.now
            do {
                _ = try await generator.generateEmbedding(for: benchmarkText)
            } catch {
                print("[BERTEmbeddingGenerator] \(displayName) failed benchmark: \(error)")
                continue
            }
            let benchMs = Int(benchStart.duration(to: ContinuousClock.now).components.seconds * 1000)
            + Int(benchStart.duration(to: ContinuousClock.now).components.attoseconds / 1_000_000_000_000_000)

            if benchMs > 100 {
                print("[BERTEmbeddingGenerator] \(displayName) rejected: \(benchMs)ms per embedding (likely CPU fallback, not NPU). Trying next model.")
                continue
            }

            print("[BERTEmbeddingGenerator] Loaded bundled model: \(name) (\(benchMs)ms per embedding, NPU confirmed)")
            return generator
        }
        print("[BERTEmbeddingGenerator] No bundled models passed NPU performance check, falling back to hashing")
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
