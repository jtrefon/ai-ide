import Foundation

@MainActor
final class CompletionBenchmarkService {
    struct BenchmarkResult: Sendable {
        let label: String
        let latencyMs: Double
        let prefixLength: Int
        let suggestionLength: Int
    }

    struct BenchmarkReport: Sendable {
        let results: [BenchmarkResult]
        let p50: Double
        let p90: Double
        let p99: Double
        let mean: Double
    }

    private let engine: InlineCompletionEngine
    private let settings: InlineCompletionSettings

    init(engine: InlineCompletionEngine, settings: InlineCompletionSettings) {
        self.engine = engine
        self.settings = settings
    }

    func runLatencyBenchmark(iterations: Int = 20) async -> BenchmarkReport {
        var results: [BenchmarkResult] = []
        let samples = CompletionBenchmarkSamples.all

        for sample in samples {
            for _ in 0..<iterations {
                let snapshot = makeSnapshot(for: sample)
                let start = CFAbsoluteTimeGetCurrent()
                _ = engine.requestCompletion(for: snapshot)
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                results.append(BenchmarkResult(
                    label: sample.label,
                    latencyMs: elapsed,
                    prefixLength: sample.prefix.count,
                    suggestionLength: 0
                ))
            }
        }

        let latencies = results.map(\.latencyMs).sorted()
        return BenchmarkReport(
            results: results,
            p50: percentile(latencies, 0.50),
            p90: percentile(latencies, 0.90),
            p99: percentile(latencies, 0.99),
            mean: latencies.reduce(0, +) / Double(max(latencies.count, 1))
        )
    }

    private func makeSnapshot(for sample: CompletionBenchmarkSamples.Sample) -> InlineCompletionEditorSnapshot {
        InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "benchmark.swift",
            language: "swift",
            buffer: sample.prefix + "█" + sample.suffix,
            cursorPosition: sample.prefix.count,
            selectionLength: 0,
            isComposingText: false,
            triggerReason: .automatic
        )
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = Int(Double(sorted.count - 1) * p)
        return sorted[index]
    }
}

enum CompletionBenchmarkSamples {
    struct Sample {
        let label: String
        let prefix: String
        let suffix: String
    }

    static let all: [Sample] = [
        Sample(
            label: "simple-expression",
            prefix: "func add(_ a: Int, _ b: Int) -> Int {\n    return a ",
            suffix: "\n}"
        ),
        Sample(
            label: "variable-declaration",
            prefix: "let result = ",
            suffix: "\nprint(result)"
        ),
        Sample(
            label: "function-call",
            prefix: "let data = fetchData()\ndata.",
            suffix: "\n// process"
        ),
        Sample(
            label: "medium-context",
            prefix: String(repeating: "let x = 1\n", count: 20) + "let y = ",
            suffix: String(repeating: "\nprint(x)", count: 5)
        ),
        Sample(
            label: "large-context",
            prefix: String(repeating: "var counter = 0\n", count: 100) + "counter",
            suffix: String(repeating: "\n// end", count: 10)
        ),
    ]
}
