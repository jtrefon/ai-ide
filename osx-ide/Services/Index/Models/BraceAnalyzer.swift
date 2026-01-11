import Foundation

struct BraceAnalysisResult {
    let openingCount: Int
    let closingCount: Int
    let startsWithClosing: Bool
}

struct BraceAnalyzer {
    func analyze(_ trimmedLine: String) -> BraceAnalysisResult {
        let startsWithClosing = trimmedLine.hasPrefix("}") || trimmedLine.hasPrefix("]") || trimmedLine.hasPrefix(")")

        let closingCount = trimmedLine.filter { $0 == "}" || $0 == "]" || $0 == ")" }.count
        let openingCount = trimmedLine.filter { $0 == "{" || $0 == "[" || $0 == "(" }.count

        return BraceAnalysisResult(
            openingCount: openingCount,
            closingCount: closingCount,
            startsWithClosing: startsWithClosing
        )
    }
}
