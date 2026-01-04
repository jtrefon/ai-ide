import Foundation

public final class SwiftHeuristicScorer: QualityScorer, @unchecked Sendable {
    public let language: CodeLanguage = .swift

    public init() {}

    public func scoreFile(path: String, content: String, context: QualityScoringContext) async -> QualityAssessment {
        let lines = content.components(separatedBy: .newlines)
        let resourceId = URL(fileURLWithPath: path).absoluteString
        let symbols = SwiftParser.parse(content: content, resourceId: resourceId)

        let typeKinds: Set<SymbolKind> = [.class, .struct, .enum, .protocol, .extension]
        let functionKinds: Set<SymbolKind> = [.function, .initializer]

        let typeSymbols = symbols.filter { typeKinds.contains($0.kind) }
            .sorted { $0.lineStart < $1.lineStart }

        let functionSymbols = symbols.filter { functionKinds.contains($0.kind) }
            .sorted { $0.lineStart < $1.lineStart }

        var children: [QualityAssessment] = []
        var fileIssues: [QualityIssue] = []

        for (idx, typeSymbol) in typeSymbols.enumerated() {
            let typeStart = typeSymbol.lineStart
            let typeEnd: Int
            if idx + 1 < typeSymbols.count {
                typeEnd = max(typeStart, typeSymbols[idx + 1].lineStart - 1)
            } else {
                typeEnd = lines.count
            }

            let methodsInType = functionSymbols.filter { $0.lineStart >= typeStart && $0.lineStart <= typeEnd }

            var methodAssessments: [QualityAssessment] = []
            var typeIssues: [QualityIssue] = []

            for method in methodsInType {
                let methodRange = inferBraceRange(lines: lines, startLine: method.lineStart)
                let methodStart = method.lineStart
                let methodEnd = methodRange?.endLine ?? method.lineStart

                let methodLines = slice(lines: lines, start: methodStart, end: methodEnd)
                let methodName = method.kind == .initializer ? "init" : method.name

                let methodAssessment = scoreMethod(name: methodName, startLine: methodStart, endLine: methodEnd, lines: methodLines)
                methodAssessments.append(methodAssessment)
                typeIssues.append(contentsOf: methodAssessment.issues)
            }

            let typeScore = aggregate(parentName: typeSymbol.name, children: methodAssessments, kind: .type)
            let typeBreakdown = QualityBreakdown(categoryScores: typeScore.breakdown.categoryScores, metrics: typeScore.breakdown.metrics)

            let typeAssessment = QualityAssessment(
                entityType: .type,
                entityName: typeSymbol.name,
                language: .swift,
                score: typeScore.score,
                breakdown: typeBreakdown,
                issues: typeIssues,
                children: methodAssessments
            )

            children.append(typeAssessment)
        }

        if typeSymbols.isEmpty {
            let standalone = scoreStandaloneFile(lines: lines)
            children.append(standalone)
        }

        let fileAggregate = aggregate(parentName: path, children: children, kind: .file)

        if fileAggregate.score <= 0 {
            fileIssues.append(QualityIssue(severity: .critical, category: .maintainability, message: "File score computed as 0; scorer malfunction"))
        }

        return QualityAssessment(
            entityType: .file,
            entityName: path,
            language: .swift,
            score: fileAggregate.score,
            breakdown: fileAggregate.breakdown,
            issues: fileIssues,
            children: children
        )
    }

    private func scoreStandaloneFile(lines: [String]) -> QualityAssessment {
        let loc = nonEmptyLineCount(lines)
        var score = 80.0
        var issues: [QualityIssue] = []

        if loc > 800 {
            score -= 30
            issues.append(QualityIssue(severity: .warning, category: .maintainability, message: "Large file (\(loc) non-empty lines)") )
        } else if loc > 400 {
            score -= 15
            issues.append(QualityIssue(severity: .info, category: .maintainability, message: "Moderately large file (\(loc) non-empty lines)") )
        }

        let breakdown = QualityBreakdown(categoryScores: [
            .readability: score,
            .complexity: score,
            .maintainability: score,
            .correctness: score,
            .architecture: score
        ], metrics: [
            "loc": Double(loc)
        ])

        return QualityAssessment(
            entityType: .type,
            entityName: "(file)",
            language: .swift,
            score: clamp(score),
            breakdown: breakdown,
            issues: issues,
            children: []
        )
    }

    private func scoreMethod(name: String, startLine: Int, endLine: Int, lines: [String]) -> QualityAssessment {
        let loc = nonEmptyLineCount(lines)
        let nesting = maxBraceNesting(lines)
        let hasTODO = lines.contains { $0.localizedCaseInsensitiveContains("TODO") || $0.localizedCaseInsensitiveContains("FIXME") }
        let switchCount = lines.filter { $0.contains("switch ") }.count
        let ifCount = lines.filter { $0.contains("if ") }.count
        let guardCount = lines.filter { $0.contains("guard ") }.count

        var score = 92.0
        var issues: [QualityIssue] = []

        if loc > 80 {
            score -= 35
            issues.append(QualityIssue(severity: .warning, category: .complexity, message: "Long method (\(loc) non-empty lines)", line: startLine))
        } else if loc > 40 {
            score -= 18
            issues.append(QualityIssue(severity: .info, category: .complexity, message: "Moderately long method (\(loc) non-empty lines)", line: startLine))
        }

        if nesting >= 5 {
            score -= 20
            issues.append(QualityIssue(severity: .warning, category: .complexity, message: "Deep nesting (max nesting \(nesting))", line: startLine))
        } else if nesting >= 3 {
            score -= 10
            issues.append(QualityIssue(severity: .info, category: .complexity, message: "Nesting depth \(nesting)", line: startLine))
        }

        if hasTODO {
            score -= 5
            issues.append(QualityIssue(severity: .info, category: .maintainability, message: "Contains TODO/FIXME", line: startLine))
        }

        let branches = switchCount + ifCount + guardCount
        if branches > 12 {
            score -= 15
            issues.append(QualityIssue(severity: .warning, category: .complexity, message: "Many branches (\(branches))", line: startLine))
        }

        let categoryScores: [QualityCategory: Double] = [
            .readability: clamp(100 - Double(loc) * 0.5 - Double(nesting) * 3),
            .complexity: clamp(100 - Double(loc) * 0.8 - Double(nesting) * 6 - Double(branches) * 1.2),
            .maintainability: clamp(score),
            .correctness: clamp(85),
            .architecture: clamp(80)
        ]

        let breakdown = QualityBreakdown(categoryScores: categoryScores, metrics: [
            "loc": Double(loc),
            "nesting": Double(nesting),
            "branches": Double(branches),
            "startLine": Double(startLine),
            "endLine": Double(endLine)
        ])

        return QualityAssessment(
            entityType: .function,
            entityName: name,
            language: .swift,
            score: clamp(score),
            breakdown: breakdown,
            issues: issues,
            children: []
        )
    }

    private enum AggregateKind {
        case file
        case type
    }

    private func aggregate(parentName: String, children: [QualityAssessment], kind: AggregateKind) -> QualityAssessment {
        guard !children.isEmpty else {
            let breakdown = QualityBreakdown(categoryScores: [
                .readability: 50,
                .complexity: 50,
                .maintainability: 50,
                .correctness: 50,
                .architecture: 50
            ])
            let entityType: QualityEntityType = (kind == .file) ? .file : .type
            return QualityAssessment(entityType: entityType, entityName: parentName, language: .swift, score: 50, breakdown: breakdown)
        }

        let avg = children.map { $0.score }.reduce(0, +) / Double(children.count)
        let minScore = children.map { $0.score }.min() ?? avg
        var score = avg

        if kind == .type {
            if children.count > 18 {
                score -= 20
            } else if children.count > 10 {
                score -= 10
            }
        }

        score = clamp((score * 0.85) + (minScore * 0.15))

        var merged: [String: Double] = [:]
        for c in children {
            for (k, v) in c.breakdown.categoryScores {
                merged[k, default: 0] += v
            }
        }
        for (k, v) in merged {
            merged[k] = v / Double(children.count)
        }

        let breakdown = QualityBreakdown(categoryScores: merged, metrics: [
            "children": Double(children.count),
            "avg": avg,
            "min": minScore
        ])

        let entityType: QualityEntityType = (kind == .file) ? .file : .type
        return QualityAssessment(entityType: entityType, entityName: parentName, language: .swift, score: score, breakdown: breakdown)
    }

    private func slice(lines: [String], start: Int, end: Int) -> [String] {
        if lines.isEmpty { return [] }
        let s = max(1, start)
        let e = min(end, lines.count)
        if s > e { return [] }
        return Array(lines[(s - 1)...(e - 1)])
    }

    private func nonEmptyLineCount(_ lines: [String]) -> Int {
        lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private func maxBraceNesting(_ lines: [String]) -> Int {
        var depth = 0
        var maxDepth = 0
        for line in lines {
            for ch in line {
                if ch == "{" { depth += 1; maxDepth = max(maxDepth, depth) }
                if ch == "}" { depth = max(0, depth - 1) }
            }
        }
        return maxDepth
    }

    private struct BraceRange {
        let endLine: Int
    }

    private func inferBraceRange(lines: [String], startLine: Int) -> BraceRange? {
        if startLine < 1 || startLine > lines.count { return nil }

        var depth = 0
        var started = false

        for idx in (startLine - 1)..<lines.count {
            let line = lines[idx]
            for ch in line {
                if ch == "{" {
                    depth += 1
                    started = true
                } else if ch == "}" {
                    if started {
                        depth = max(0, depth - 1)
                        if depth == 0 {
                            return BraceRange(endLine: idx + 1)
                        }
                    }
                }
            }

            if started, idx - (startLine - 1) > 600 {
                return BraceRange(endLine: idx + 1)
            }
        }

        return nil
    }

    private func clamp(_ v: Double) -> Double {
        max(0, min(100, v))
    }
}
