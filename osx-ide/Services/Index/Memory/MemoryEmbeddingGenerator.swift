import Foundation

public protocol MemoryEmbeddingGenerating: Sendable {
    var modelIdentifier: String { get }
    func generateEmbedding(for text: String) async throws -> [Float]
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
