import CoreML
import Foundation
import Testing
@testable import osx_ide

/// Embedding model performance metrics
struct EmbeddingPerformanceMetrics: Sendable {
    let testId: String
    let modelId: String
    let modelName: String
    let dimensions: Int
    let textLength: Int
    let embeddingDuration: TimeInterval
    let coldStartDuration: TimeInterval
    let peakMemoryMB: UInt64
    let usesNPU: Bool
    let timestamp: Date
    
    /// Embeddings per second
    var embeddingsPerSecond: Double {
        guard embeddingDuration > 0 else { return 0 }
        return 1.0 / embeddingDuration
    }
    
    /// Memory efficiency (dimensions per MB)
    var memoryEfficiency: Double {
        guard peakMemoryMB > 0 else { return 0 }
        return Double(dimensions) / Double(peakMemoryMB)
    }
    
    var summary: String {
        """
        [Embedding Metrics - \(modelId)]
        Model: \(modelName)
        Dimensions: \(dimensions)
        Text Length: \(textLength) chars
        Embedding Duration: \(String(format: "%.3f", embeddingDuration * 1000))ms
        Cold Start: \(String(format: "%.3f", coldStartDuration))s
        Embeddings/Second: \(String(format: "%.1f", embeddingsPerSecond))
        Peak Memory: \(peakMemoryMB)MB
        NPU Accelerated: \(usesNPU ? "Yes" : "No")
        """
    }
    
    static var csvHeader: String {
        "test_id,model_id,model_name,dimensions,text_length,embedding_ms,cold_start_s,embeddings_per_sec,peak_memory_mb,uses_npu,timestamp"
    }
    
    var csvRow: String {
        "\(testId),\(modelId),\(modelName.replacingOccurrences(of: ",", with: ";")),\(dimensions),\(textLength),\(String(format: "%.3f", embeddingDuration * 1000)),\(String(format: "%.3f", coldStartDuration)),\(String(format: "%.1f", embeddingsPerSecond)),\(peakMemoryMB),\(usesNPU),\(ISO8601DateFormatter().string(from: timestamp))"
    }
}

/// Embedding quality metrics (semantic similarity tests)
struct EmbeddingQualityMetrics: Sendable {
    let testId: String
    let modelId: String
    let similarPairsScore: Double  // Average similarity for similar text pairs
    let dissimilarPairsScore: Double  // Average similarity for dissimilar text pairs
    let discriminationScore: Double  // Difference between similar and dissimilar
    
    var summary: String {
        """
        [Quality Metrics - \(modelId)]
        Similar Pairs Score: \(String(format: "%.3f", similarPairsScore))
        Dissimilar Pairs Score: \(String(format: "%.3f", dissimilarPairsScore))
        Discrimination Score: \(String(format: "%.3f", discriminationScore))
        """
    }
}

/// Complete benchmark result for a single model
struct EmbeddingBenchmarkResult: Sendable {
    let modelId: String
    let modelName: String
    let dimensions: Int
    let performanceMetrics: [EmbeddingPerformanceMetrics]
    let qualityMetrics: EmbeddingQualityMetrics?
    
    /// Average embedding duration in milliseconds
    var avgEmbeddingMs: Double {
        guard !performanceMetrics.isEmpty else { return 0 }
        return performanceMetrics.reduce(0) { $0 + $1.embeddingDuration * 1000 } / Double(performanceMetrics.count)
    }
    
    /// Average embeddings per second
    var avgEmbeddingsPerSecond: Double {
        guard !performanceMetrics.isEmpty else { return 0 }
        return performanceMetrics.reduce(0) { $0 + $1.embeddingsPerSecond } / Double(performanceMetrics.count)
    }
    
    /// Overall score (0-100) combining speed, quality, and efficiency
    var overallScore: Double {
        var score = 0.0
        
        // Speed score (faster = better, max 40 points)
        // 100+ embeddings/sec = 40 points, 10/sec = 10 points
        let speedScore = min(40, max(10, avgEmbeddingsPerSecond * 0.4))
        score += speedScore
        
        // Quality score (discrimination, max 40 points)
        if let quality = qualityMetrics {
            // Discrimination > 0.5 = good, > 0.7 = excellent
            let qualityScore = min(40, max(0, quality.discriminationScore * 50))
            score += qualityScore
        }
        
        // Efficiency score (dimensions per MB, max 20 points)
        if let first = performanceMetrics.first {
            let efficiencyScore = min(20, max(5, first.memoryEfficiency * 0.1))
            score += efficiencyScore
        }
        
        return score
    }
    
    var summary: String {
        """
        === \(modelName) ===
        Dimensions: \(dimensions)
        Avg Embedding Time: \(String(format: "%.2f", avgEmbeddingMs))ms
        Avg Embeddings/Sec: \(String(format: "%.1f", avgEmbeddingsPerSecond))
        Overall Score: \(String(format: "%.1f", overallScore))/100
        \(qualityMetrics?.summary ?? "No quality metrics")
        """
    }
}

/// Actor for collecting embedding benchmark metrics
actor EmbeddingBenchmarkCollector {
    static let shared = EmbeddingBenchmarkCollector()
    
    private var performanceMetrics: [EmbeddingPerformanceMetrics] = []
    private var qualityMetrics: [String: EmbeddingQualityMetrics] = [:]
    private var currentTestId: String?
    
    private init() {}
    
    func startTest(testId: String) {
        currentTestId = testId
        performanceMetrics.removeAll()
        qualityMetrics.removeAll()
    }
    
    func recordPerformance(_ metric: EmbeddingPerformanceMetrics) {
        performanceMetrics.append(metric)
    }
    
    func recordQuality(_ metric: EmbeddingQualityMetrics) {
        qualityMetrics[metric.modelId] = metric
    }
    
    func getResults() -> [EmbeddingBenchmarkResult] {
        // Group by model
        var modelIds = Set(performanceMetrics.map(\.modelId))
        var results: [EmbeddingBenchmarkResult] = []
        
        for modelId in modelIds {
            let modelMetrics = performanceMetrics.filter { $0.modelId == modelId }
            guard let first = modelMetrics.first else { continue }
            
            let result = EmbeddingBenchmarkResult(
                modelId: modelId,
                modelName: first.modelName,
                dimensions: first.dimensions,
                performanceMetrics: modelMetrics,
                qualityMetrics: qualityMetrics[modelId]
            )
            results.append(result)
        }
        
        // Sort by overall score descending
        return results.sorted { $0.overallScore > $1.overallScore }
    }
    
    func exportCSV() -> String {
        var lines = [EmbeddingPerformanceMetrics.csvHeader]
        lines.append(contentsOf: performanceMetrics.map { $0.csvRow })
        return lines.joined(separator: "\n")
    }
    
    func exportScorecard() -> String {
        let results = getResults()
        var lines = [
            "EMBEDDING MODEL BENCHMARK SCORECARD",
            "=====================================",
            ""
        ]
        
        for (index, result) in results.enumerated() {
            lines.append("#\(index + 1) - Score: \(String(format: "%.1f", result.overallScore))/100")
            lines.append(result.summary)
            lines.append("")
        }
        
        lines.append("=====================================")
        lines.append("Ranking based on: Speed (40pts) + Quality (40pts) + Efficiency (20pts)")
        
        return lines.joined(separator: "\n")
    }
    
    func clear() {
        performanceMetrics.removeAll()
        qualityMetrics.removeAll()
        currentTestId = nil
    }
}

/// Test helper for measuring embedding performance
struct EmbeddingTimer {
    private let startTime: Date
    private let startMemory: UInt64
    
    init() {
        self.startTime = Date()
        self.startMemory = Self.reportMemory()
    }
    
    func measure(coldStart: Bool = false) -> (duration: TimeInterval, memory: UInt64) {
        let endTime = Date()
        let endMemory = Self.reportMemory()
        return (
            duration: endTime.timeIntervalSince(startTime),
            memory: max(startMemory, endMemory)
        )
    }
    
    static func reportMemory() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size / 1_048_576 : 0
    }
}

// MARK: - Benchmark Tests

@Suite("Embedding Model Benchmarks")
struct EmbeddingModelBenchmarkTests {
    
    /// Test texts for benchmarking
    static let testTexts = [
        "func calculateSum(_ a: Int, _ b: Int) -> Int { return a + b }",
        "The quick brown fox jumps over the lazy dog.",
        "This is a longer piece of text that contains multiple sentences. It tests how the embedding model handles longer inputs with various punctuation marks, numbers like 123, and special characters like @#$%.",
        "class UserAuthentication {\n    private let tokenStore: TokenStore\n    func authenticate(credentials: Credentials) async throws -> AuthToken {\n        // Implementation here\n    }\n}",
        "import Foundation\n\n@main\nstruct MyApp {\n    static func main() async {\n        print(\"Hello, World!\")\n    }\n}",
    ]
    
    /// Similar text pairs for quality testing
    static let similarPairs = [
        ("func add(a: Int, b: Int) -> Int", "function add(a: number, b: number): number"),
        ("The cat sat on the mat", "A cat was sitting on a mat"),
        ("class UserService { func getUser() }", "class UserManager { func fetchUser() }"),
        ("HTTP request failed with error", "Network request returned an error"),
        ("Sort array in ascending order", "Order list from smallest to largest"),
    ]
    
    /// Dissimilar text pairs for quality testing
    static let dissimilarPairs = [
        ("func add(a: Int, b: Int) -> Int", "The weather is sunny today"),
        ("The cat sat on the mat", "Database connection pool configuration"),
        ("class UserService { func getUser() }", "Recipe for chocolate cake"),
        ("HTTP request failed with error", "Mountain climbing expedition"),
        ("Sort array in ascending order", "Jazz music concert tonight"),
    ]
    
    @Test("Benchmark all bundled embedding models")
    func benchmarkAllModels() async throws {
        let testId = "embedding-benchmark-\(UUID().uuidString.prefix(8))"
        await EmbeddingBenchmarkCollector.shared.startTest(testId: String(testId))
        
        print("\n" + String(repeating: "=", count: 60))
        print("EMBEDDING MODEL BENCHMARK - \(testId)")
        print(String(repeating: "=", count: 60) + "\n")
        
        let models = BERTEmbeddingGeneratorFactory.bundledModels
        
        for (name, dimensions, displayName) in models {
            print("\n--- Testing: \(displayName) ---")
            
            // Measure cold start
            let coldStartTimer = EmbeddingTimer()
            guard let generator = await BERTEmbeddingGenerator.loadBundledModel(
                modelName: name,
                dimensions: dimensions
            ) else {
                print("⚠️ Failed to load model: \(name)")
                continue
            }
            let coldStart = coldStartTimer.measure(coldStart: true)
            print("Cold start: \(String(format: "%.3f", coldStart.duration))s")
            print("NPU Accelerated: \(generator.usesNPU ? "Yes ✓" : "No ✗")")
            
            // Warm up
            _ = try? await generator.generateEmbedding(for: "Warm up text")
            
            // Benchmark each test text
            for text in Self.testTexts {
                let timer = EmbeddingTimer()
                
                do {
                    let embedding = try await generator.generateEmbedding(for: text)
                    let measured = timer.measure()
                    
                    let metric = EmbeddingPerformanceMetrics(
                        testId: String(testId),
                        modelId: name,
                        modelName: displayName,
                        dimensions: dimensions,
                        textLength: text.count,
                        embeddingDuration: measured.duration,
                        coldStartDuration: coldStart.duration,
                        peakMemoryMB: measured.memory,
                        usesNPU: generator.usesNPU,
                        timestamp: Date()
                    )
                    
                    await EmbeddingBenchmarkCollector.shared.recordPerformance(metric)
                    
                    print("  [\(text.prefix(30))...] \(String(format: "%.2f", measured.duration * 1000))ms, \(embedding.count)D")
                } catch {
                    print("  ⚠️ Failed: \(error)")
                }
            }
            
            // Quality tests
            await runQualityTests(generator: generator, modelId: name, testId: String(testId))
        }
        
        // Print scorecard
        let scorecard = await EmbeddingBenchmarkCollector.shared.exportScorecard()
        print("\n" + scorecard)
        
        // Export CSV
        let csv = await EmbeddingBenchmarkCollector.shared.exportCSV()
        let csvPath = FileManager.default.temporaryDirectory.appendingPathComponent("embedding-benchmark-\(testId).csv")
        try? csv.write(to: csvPath, atomically: true, encoding: .utf8)
        print("\nCSV exported to: \(csvPath.path)")
    }
    
    private func runQualityTests(generator: BERTEmbeddingGenerator, modelId: String, testId: String) async {
        do {
            // Test similar pairs
            var similarScores: [Double] = []
            for (text1, text2) in Self.similarPairs {
                let emb1 = try await generator.generateEmbedding(for: text1)
                let emb2 = try await generator.generateEmbedding(for: text2)
                let similarity = cosineSimilarity(emb1, emb2)
                similarScores.append(similarity)
            }
            
            // Test dissimilar pairs
            var dissimilarScores: [Double] = []
            for (text1, text2) in Self.dissimilarPairs {
                let emb1 = try await generator.generateEmbedding(for: text1)
                let emb2 = try await generator.generateEmbedding(for: text2)
                let similarity = cosineSimilarity(emb1, emb2)
                dissimilarScores.append(similarity)
            }
            
            let avgSimilar = similarScores.reduce(0, +) / Double(similarScores.count)
            let avgDissimilar = dissimilarScores.reduce(0, +) / Double(dissimilarScores.count)
            let discrimination = avgSimilar - avgDissimilar
            
            let quality = EmbeddingQualityMetrics(
                testId: testId,
                modelId: modelId,
                similarPairsScore: avgSimilar,
                dissimilarPairsScore: avgDissimilar,
                discriminationScore: discrimination
            )
            
            await EmbeddingBenchmarkCollector.shared.recordQuality(quality)
            
            print("  Quality: Similar=\(String(format: "%.3f", avgSimilar)), Dissimilar=\(String(format: "%.3f", avgDissimilar)), Discrimination=\(String(format: "%.3f", discrimination))")
        } catch {
            print("  ⚠️ Quality tests failed: \(error)")
        }
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? Double(dotProduct / denominator) : 0
    }
    
    @Test("Compare embedding models speed")
    func compareSpeed() async throws {
        print("\n--- Embedding Speed Comparison ---")
        
        let testText = "This is a test sentence for comparing embedding generation speed across different models."
        let iterations = 10
        
        let models = BERTEmbeddingGeneratorFactory.bundledModels
        
        for (name, dimensions, displayName) in models {
            guard let generator = await BERTEmbeddingGenerator.loadBundledModel(
                modelName: name,
                dimensions: dimensions
            ) else {
                continue
            }
            
            // Warm up
            _ = try? await generator.generateEmbedding(for: testText)
            
            // Measure
            let start = Date()
            for _ in 0..<iterations {
                _ = try await generator.generateEmbedding(for: testText)
            }
            let duration = Date().timeIntervalSince(start)
            let avgMs = (duration / Double(iterations)) * 1000
            
            print("\(displayName): \(String(format: "%.2f", avgMs))ms avg (\(String(format: "%.1f", Double(iterations) / duration)) embeddings/sec)")
        }
    }
    
    @Test("Test embedding dimensions")
    func testDimensions() async throws {
        print("\n--- Embedding Dimensions Test ---")
        
        let testText = "Test embedding dimensions"
        
        let models = BERTEmbeddingGeneratorFactory.bundledModels
        
        for (name, expectedDims, displayName) in models {
            guard let generator = await BERTEmbeddingGenerator.loadBundledModel(
                modelName: name,
                dimensions: expectedDims
            ) else {
                print("⚠️ \(displayName): Failed to load")
                continue
            }
            
            do {
                let embedding = try await generator.generateEmbedding(for: testText)
                let actualDims = embedding.count
                
                if actualDims == expectedDims {
                    print("✅ \(displayName): \(actualDims)D (expected: \(expectedDims)D)")
                } else {
                    print("⚠️ \(displayName): \(actualDims)D (expected: \(expectedDims)D)")
                }
            } catch {
                print("❌ \(displayName): \(error)")
            }
        }
    }
}
