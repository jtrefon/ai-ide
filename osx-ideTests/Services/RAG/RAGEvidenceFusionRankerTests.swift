import XCTest
@testable import osx_ide

final class RAGEvidenceFusionRankerTests: XCTestCase {
    var ranker: RAGEvidenceFusionRanker!
    
    override func setUp() {
        super.setUp()
        ranker = RAGEvidenceFusionRanker()
    }
    
    override func tearDown() {
        ranker = nil
        super.tearDown()
    }
    
    // MARK: - Ranking Determinism Tests
    
    func testRankingIsDeterministic() {
        let candidates = createTestCandidates()
        let userInput = "fix authentication bug"
        let intent = RetrievalIntent.bugfix
        
        let result1 = ranker.rank(candidates: candidates, userInput: userInput, intent: intent)
        let result2 = ranker.rank(candidates: candidates, userInput: userInput, intent: intent)
        
        XCTAssertEqual(result1.count, result2.count, "Ranking should produce same count")
        
        for (index, card) in result1.enumerated() {
            let card2 = result2[index]
            XCTAssertEqual(card.filePath, card2.filePath, "Ranking order should be deterministic at index \(index)")
            XCTAssertEqual(card.totalScore, card2.totalScore, accuracy: 0.0001, "Scores should be deterministic")
        }
    }
    
    func testEmptyCandidatesReturnsEmptyResult() {
        let result = ranker.rank(candidates: [], userInput: "test", intent: .other)
        XCTAssertTrue(result.isEmpty, "Empty candidates should return empty result")
    }
    
    // MARK: - Intent Weighting Tests
    
    func testBugfixIntentBoostsRelevantEvidence() {
        let bugfixCandidate = createCandidate(
            filePath: "AuthService.swift",
            evidenceType: .symbol,
            searchableText: "authentication login bug error fix",
            qualityScore: 0.7
        )
        let unrelatedCandidate = createCandidate(
            filePath: "UIHelper.swift",
            evidenceType: .symbol,
            searchableText: "button color theme style",
            qualityScore: 0.7
        )
        
        let result = ranker.rank(
            candidates: [bugfixCandidate, unrelatedCandidate],
            userInput: "fix authentication bug",
            intent: .bugfix
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].filePath.contains("AuthService"), "Bugfix-relevant evidence should rank higher")
    }
    
    func testFeatureIntentBoostsArchitectureEvidence() {
        let architectureCandidate = createCandidate(
            filePath: "Services/CoreService.swift",
            evidenceType: .summary,
            searchableText: "service architecture pattern dependency injection",
            qualityScore: 0.8
        )
        let implementationCandidate = createCandidate(
            filePath: "Utils/StringHelper.swift",
            evidenceType: .symbol,
            searchableText: "string trim uppercase helper",
            qualityScore: 0.8
        )
        
        let result = ranker.rank(
            candidates: [architectureCandidate, implementationCandidate],
            userInput: "add new payment service",
            intent: .feature
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].filePath.contains("CoreService"), "Architecture evidence should rank higher for features")
    }
    
    // MARK: - Score Component Tests
    
    func testQualityScoreBoostsHighQualityCode() {
        let highQuality = createCandidate(
            filePath: "HighQuality.swift",
            evidenceType: .symbol,
            searchableText: "test function",
            qualityScore: 0.9
        )
        let lowQuality = createCandidate(
            filePath: "LowQuality.swift",
            evidenceType: .symbol,
            searchableText: "test function",
            qualityScore: 0.3
        )
        
        let result = ranker.rank(
            candidates: [highQuality, lowQuality],
            userInput: "test function",
            intent: .other
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].scoreComponents.qualityBoost > result[1].scoreComponents.qualityBoost,
                      "Higher quality should produce higher quality boost")
    }
    
    func testFreshnessBoostsRecentCode() {
        let recentCandidate = createCandidate(
            filePath: "Recent.swift",
            evidenceType: .symbol,
            searchableText: "function",
            qualityScore: 0.7,
            freshness: 1.0
        )
        let staleCandidate = createCandidate(
            filePath: "Stale.swift",
            evidenceType: .symbol,
            searchableText: "function",
            qualityScore: 0.7,
            freshness: 0.1
        )
        
        let result = ranker.rank(
            candidates: [recentCandidate, staleCandidate],
            userInput: "function",
            intent: .other
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].scoreComponents.recency > result[1].scoreComponents.recency,
                      "Recent code should have higher recency score")
    }
    
    func testArchitectureProximityBoostsServicesLayer() {
        let serviceCandidate = createCandidate(
            filePath: "Services/AuthService.swift",
            evidenceType: .symbol,
            searchableText: "authentication",
            qualityScore: 0.7
        )
        let utilCandidate = createCandidate(
            filePath: "Utils/Helper.swift",
            evidenceType: .symbol,
            searchableText: "authentication",
            qualityScore: 0.7
        )
        
        let result = ranker.rank(
            candidates: [serviceCandidate, utilCandidate],
            userInput: "authentication",
            intent: .feature
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].scoreComponents.architectureProximity > result[1].scoreComponents.architectureProximity,
                      "Services layer should have higher architecture proximity")
    }
    
    // MARK: - Evidence Type Tests
    
    func testSummaryEvidenceRanksHigherForOverview() {
        let summaryCandidate = createCandidate(
            filePath: "README.md",
            evidenceType: .summary,
            searchableText: "project overview architecture",
            qualityScore: 0.8
        )
        let symbolCandidate = createCandidate(
            filePath: "Service.swift",
            evidenceType: .symbol,
            searchableText: "function implementation",
            qualityScore: 0.8
        )
        
        let result = ranker.rank(
            candidates: [summaryCandidate, symbolCandidate],
            userInput: "explain project architecture",
            intent: .explanation
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].evidenceType, .summary, "Summary should rank higher for explanation intent")
    }
    
    func testMemoryEvidenceIncludedInResults() {
        let memoryCandidate = createCandidate(
            filePath: "memory://context",
            evidenceType: .memory,
            searchableText: "previous discussion about feature",
            qualityScore: nil
        )
        let symbolCandidate = createCandidate(
            filePath: "Service.swift",
            evidenceType: .symbol,
            searchableText: "feature implementation",
            qualityScore: 0.7
        )
        
        let result = ranker.rank(
            candidates: [memoryCandidate, symbolCandidate],
            userInput: "feature",
            intent: .feature
        )
        
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.evidenceType == .memory }), "Memory evidence should be included")
    }
    
    // MARK: - Score Normalization Tests
    
    func testScoresAreNormalizedBetweenZeroAndOne() {
        let candidates = createTestCandidates()
        let result = ranker.rank(candidates: candidates, userInput: "test", intent: .other)
        
        for card in result {
            XCTAssertGreaterThanOrEqual(card.totalScore, 0.0, "Score should be >= 0")
            XCTAssertLessThanOrEqual(card.totalScore, 1.0, "Score should be <= 1")
        }
    }
    
    func testScoreComponentsAreMeaningful() {
        let candidate = createCandidate(
            filePath: "Test.swift",
            evidenceType: .symbol,
            searchableText: "test function implementation",
            qualityScore: 0.8,
            freshness: 0.9
        )
        
        let result = ranker.rank(
            candidates: [candidate],
            userInput: "test function",
            intent: .other
        )
        
        XCTAssertEqual(result.count, 1)
        let card = result[0]
        
        XCTAssertGreaterThan(card.scoreComponents.semanticSimilarity, 0.0, "Should have semantic similarity")
        XCTAssertGreaterThan(card.scoreComponents.qualityBoost, 0.0, "Should have quality boost")
        XCTAssertGreaterThan(card.scoreComponents.recency, 0.0, "Should have recency score")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCandidates() -> [RAGEvidenceCandidate] {
        return [
            createCandidate(filePath: "Services/AuthService.swift", evidenceType: .symbol, searchableText: "authentication login", qualityScore: 0.8),
            createCandidate(filePath: "Models/User.swift", evidenceType: .symbol, searchableText: "user model data", qualityScore: 0.7),
            createCandidate(filePath: "README.md", evidenceType: .summary, searchableText: "project overview", qualityScore: nil),
            createCandidate(filePath: "Utils/Helper.swift", evidenceType: .symbol, searchableText: "utility functions", qualityScore: 0.6)
        ]
    }
    
    private func createCandidate(
        filePath: String,
        evidenceType: EvidenceType,
        searchableText: String,
        qualityScore: Double?,
        freshness: Double = 0.8
    ) -> RAGEvidenceCandidate {
        return RAGEvidenceCandidate(
            filePath: filePath,
            evidenceType: evidenceType,
            lineStart: 1,
            lineEnd: 10,
            preview: searchableText,
            searchableText: searchableText,
            qualityScore: qualityScore,
            freshness: freshness
        )
    }
}
