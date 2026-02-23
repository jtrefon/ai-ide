import CoreML
import Foundation

public protocol MemoryEmbeddingGenerating: Sendable {
    var modelIdentifier: String { get }
    func generateEmbedding(for text: String) async throws -> [Float]
}

public enum MemoryEmbeddingGeneratorFactory {
    /// Synchronous factory method - returns HashingMemoryEmbeddingGenerator for fast startup
    /// CoreML loading is intentionally skipped here to avoid blocking during app startup.
    /// Use makeDefaultAsync() if you need CoreML embeddings and can handle async loading.
    public static func makeDefault(projectRoot: URL?) -> any MemoryEmbeddingGenerating {
        // Always use fast hashing embeddings for synchronous initialization
        // CoreML model loading can take MINUTES on first run due to NPU compilation
        return HashingMemoryEmbeddingGenerator()
    }

    /// Async factory method - loads models off the main thread
    public static func makeDefaultAsync(projectRoot: URL?) async -> any MemoryEmbeddingGenerating {
        // Load model off main thread to avoid blocking UI
        if let coreML = await CoreMLTextEmbeddingGenerator.makeDefaultAsync(
            projectRoot: projectRoot)
        {
            return coreML
        }
        return HashingMemoryEmbeddingGenerator()
    }
}

public struct HashingMemoryEmbeddingGenerator: MemoryEmbeddingGenerating {
    public let modelIdentifier: String = "hashing_v1"
    private let dimensions: Int

    public init(dimensions: Int = 256) {
        self.dimensions = max(32, dimensions)
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }

        var vector = Array(repeating: Float(0), count: dimensions)
        for token in tokens {
            let bucket = abs(token.hashValue) % dimensions
            vector[bucket] += 1
        }

        normalizeInPlace(&vector)
        return vector
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func normalizeInPlace(_ vector: inout [Float]) {
        let sumSquares = vector.reduce(Float(0)) { partial, value in
            partial + (value * value)
        }
        guard sumSquares > 0 else { return }
        let norm = sqrt(sumSquares)
        for index in vector.indices {
            vector[index] /= norm
        }
    }
}

public final class CoreMLTextEmbeddingGenerator: MemoryEmbeddingGenerating, @unchecked Sendable {
    public let modelIdentifier: String

    private let model: MLModel
    private let inputFeatureName: String
    private let outputFeatureName: String

    private init(
        model: MLModel, modelIdentifier: String, inputFeatureName: String, outputFeatureName: String
    ) {
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.inputFeatureName = inputFeatureName
        self.outputFeatureName = outputFeatureName
    }

    /// Synchronous factory method (legacy, may block during model loading)
    public static func makeDefault(projectRoot: URL?) -> CoreMLTextEmbeddingGenerator? {
        let defaultCandidates = candidateModelURLs(projectRoot: projectRoot)

        for modelURL in defaultCandidates
        where FileManager.default.fileExists(atPath: modelURL.path) {
            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .cpuAndNeuralEngine

                let model = try MLModel(contentsOf: modelURL, configuration: configuration)
                guard let inputFeatureName = findStringInputFeatureName(model) else { continue }
                guard let outputFeatureName = findMultiArrayOutputFeatureName(model) else {
                    continue
                }

                return CoreMLTextEmbeddingGenerator(
                    model: model,
                    modelIdentifier: "coreml_ane_\(modelURL.lastPathComponent)",
                    inputFeatureName: inputFeatureName,
                    outputFeatureName: outputFeatureName
                )
            } catch {
                continue
            }
        }

        return nil
    }

    /// Async factory method - loads models off the calling thread
    public static func makeDefaultAsync(projectRoot: URL?) async -> CoreMLTextEmbeddingGenerator? {
        await Task.detached(priority: .userInitiated) {
            Self.makeDefault(projectRoot: projectRoot)
        }.value
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let provider = DictionaryFeatureProvider(values: [
            inputFeatureName: MLFeatureValue(string: trimmed)
        ])
        let output = try await model.prediction(from: provider)

        guard let array = output.featureValue(for: outputFeatureName)?.multiArrayValue else {
            throw NSError(
                domain: "CoreMLTextEmbeddingGenerator", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Expected multi-array output for embedding generation"
                ])
        }

        return Self.makeFloatVector(from: array)
    }

    private static func candidateModelURLs(projectRoot: URL?) -> [URL] {
        var urls: [URL] = []

        // 1. Check Project specific overrides in .ide/models/
        if let projectRoot {
            let modelDir = projectRoot.appendingPathComponent(".ide", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)

            for model in EmbeddingModelCatalog.availableModels {
                urls.append(modelDir.appendingPathComponent(model.fileName))
            }

            // Legacy fallbacks
            urls.append(modelDir.appendingPathComponent("text-embedding.mlmodelc"))
            urls.append(modelDir.appendingPathComponent("embedding.mlmodelc"))
        }

        // 2. Check Global App Support Store via LocalModelFileStore
        for model in EmbeddingModelCatalog.availableModels {
            if let url = try? LocalModelFileStore.modelsRootDirectory()
                .appendingPathComponent("embeddings", isDirectory: true)
                .appendingPathComponent(model.id, isDirectory: true)
                .appendingPathComponent(model.fileName)
            {
                urls.append(url)
            }
        }

        // 3. Check Bundle Fallbacks
        if let bundled = Bundle.main.url(forResource: "text-embedding", withExtension: "mlmodelc") {
            urls.append(bundled)
        }
        if let bundled = Bundle.main.url(forResource: "embedding", withExtension: "mlmodelc") {
            urls.append(bundled)
        }
        return urls
    }

    private static func findStringInputFeatureName(_ model: MLModel) -> String? {
        model.modelDescription.inputDescriptionsByName.first(where: { _, description in
            description.type == .string
        })?.key
    }

    private static func findMultiArrayOutputFeatureName(_ model: MLModel) -> String? {
        model.modelDescription.outputDescriptionsByName.first(where: { _, description in
            description.type == .multiArray
        })?.key
    }

    private static func makeFloatVector(from array: MLMultiArray) -> [Float] {
        let count = array.count
        var vector = Array(repeating: Float(0), count: count)

        switch array.dataType {
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: count)
            for index in 0..<count {
                vector[index] = Float(pointer[index])
            }
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: count)
            for index in 0..<count {
                vector[index] = pointer[index]
            }
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: UInt16.self, capacity: count)
            for index in 0..<count {
                vector[index] = Float(Float16(bitPattern: pointer[index]))
            }
        default:
            for index in 0..<count {
                vector[index] = array[index].floatValue
            }
        }

        let sumSquares = vector.reduce(Float(0)) { partial, value in
            partial + (value * value)
        }
        if sumSquares > 0 {
            let norm = sqrt(sumSquares)
            for index in vector.indices {
                vector[index] /= norm
            }
        }

        return vector
    }
}

private final class DictionaryFeatureProvider: NSObject, MLFeatureProvider {
    let values: [String: MLFeatureValue]

    init(values: [String: MLFeatureValue]) {
        self.values = values
    }

    var featureNames: Set<String> {
        Set(values.keys)
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        values[featureName]
    }
}
