import Foundation

/// Performance metrics for local model inference testing
struct InferencePerformanceMetrics: Sendable {
    let testId: String
    let modelId: String
    let conversationTurn: Int
    let promptTokenCount: Int
    let outputTokenCount: Int
    let timeToFirstToken: TimeInterval
    let totalDuration: TimeInterval
    let peakMemoryMB: UInt64
    let timestamp: Date
    
    var tokensPerSecond: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(outputTokenCount) / totalDuration
    }
    
    var promptTokensPerSecond: Double {
        guard totalDuration > 0 else { return 0 }
        return Double(promptTokenCount) / totalDuration
    }
    
    /// Create a summary string for logging
    var summary: String {
        """
        [Inference Metrics - \(testId)]
        Model: \(modelId)
        Turn: \(conversationTurn)
        Prompt Tokens: \(promptTokenCount)
        Output Tokens: \(outputTokenCount)
        Time to First Token: \(String(format: "%.3f", timeToFirstToken))s
        Total Duration: \(String(format: "%.3f", totalDuration))s
        Tokens/Second: \(String(format: "%.1f", tokensPerSecond))
        Peak Memory: \(peakMemoryMB)MB
        """
    }
    
    /// CSV header for metrics export
    static var csvHeader: String {
        "test_id,model_id,turn,prompt_tokens,output_tokens,ttft_s,total_s,tokens_per_sec,peak_memory_mb,timestamp"
    }
    
    /// CSV row for metrics export
    var csvRow: String {
        "\(testId),\(modelId),\(conversationTurn),\(promptTokenCount),\(outputTokenCount),\(String(format: "%.3f", timeToFirstToken)),\(String(format: "%.3f", totalDuration)),\(String(format: "%.1f", tokensPerSecond)),\(peakMemoryMB),\(ISO8601DateFormatter().string(from: timestamp))"
    }
}

/// Collector for aggregating performance metrics across test runs
actor InferenceMetricsCollector {
    static let shared = InferenceMetricsCollector()
    
    private var metrics: [InferencePerformanceMetrics] = []
    private var currentTestId: String?
    private var turnCount: Int = 0
    
    private init() {}
    
    func startTest(testId: String) {
        currentTestId = testId
        turnCount = 0
    }
    
    func endTest() {
        currentTestId = nil
        turnCount = 0
    }
    
    func recordMetrics(_ metric: InferencePerformanceMetrics) {
        metrics.append(metric)
    }
    
    func incrementTurn() -> Int {
        turnCount += 1
        return turnCount
    }
    
    func getAllMetrics() -> [InferencePerformanceMetrics] {
        metrics
    }
    
    func getMetrics(forTestId testId: String) -> [InferencePerformanceMetrics] {
        metrics.filter { $0.testId == testId }
    }
    
    func clearMetrics() {
        metrics.removeAll()
    }
    
    /// Export all metrics as CSV
    func exportCSV() -> String {
        var lines = [InferencePerformanceMetrics.csvHeader]
        lines.append(contentsOf: metrics.map { $0.csvRow })
        return lines.joined(separator: "\n")
    }
    
    /// Calculate aggregate statistics
    func aggregateStats() -> AggregateStats? {
        guard !metrics.isEmpty else { return nil }
        
        let totalTokens = metrics.reduce(0) { $0 + $1.outputTokenCount }
        let totalDuration = metrics.reduce(0.0) { $0 + $1.totalDuration }
        let avgTokensPerSecond = totalDuration > 0 ? Double(totalTokens) / totalDuration : 0
        let avgTimeToFirstToken = metrics.reduce(0.0) { $0 + $1.timeToFirstToken } / Double(metrics.count)
        let peakMemory = metrics.map(\.peakMemoryMB).max() ?? 0
        
        return AggregateStats(
            totalInferences: metrics.count,
            totalTokens: totalTokens,
            totalDuration: totalDuration,
            avgTokensPerSecond: avgTokensPerSecond,
            avgTimeToFirstToken: avgTimeToFirstToken,
            peakMemoryMB: peakMemory
        )
    }
    
    struct AggregateStats: Sendable {
        let totalInferences: Int
        let totalTokens: Int
        let totalDuration: TimeInterval
        let avgTokensPerSecond: Double
        let avgTimeToFirstToken: TimeInterval
        let peakMemoryMB: UInt64
        
        var summary: String {
            """
            [Aggregate Performance Stats]
            Total Inferences: \(totalInferences)
            Total Tokens: \(totalTokens)
            Total Duration: \(String(format: "%.2f", totalDuration))s
            Avg Tokens/Second: \(String(format: "%.1f", avgTokensPerSecond))
            Avg Time to First Token: \(String(format: "%.3f", avgTimeToFirstToken))s
            Peak Memory: \(peakMemoryMB)MB
            """
        }
    }
}

/// Helper for measuring inference performance
struct InferenceTimer {
    private let startTime: Date
    private var firstTokenTime: Date?
    private let startMemory: UInt64
    
    init() {
        self.startTime = Date()
        self.startMemory = Self.reportMemory()
    }
    
    mutating func recordFirstToken() {
        if firstTokenTime == nil {
            firstTokenTime = Date()
        }
    }
    
    func finalize(
        testId: String,
        modelId: String,
        turn: Int,
        promptTokens: Int,
        outputTokens: Int
    ) -> InferencePerformanceMetrics {
        let endTime = Date()
        let endMemory = Self.reportMemory()
        
        return InferencePerformanceMetrics(
            testId: testId,
            modelId: modelId,
            conversationTurn: turn,
            promptTokenCount: promptTokens,
            outputTokenCount: outputTokens,
            timeToFirstToken: firstTokenTime?.timeIntervalSince(startTime) ?? 0,
            totalDuration: endTime.timeIntervalSince(startTime),
            peakMemoryMB: max(startMemory, endMemory),
            timestamp: startTime
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
