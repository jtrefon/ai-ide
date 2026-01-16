import Foundation

public final class SwiftHeuristicScorer: QualityScorer, @unchecked Sendable {
    public let language: CodeLanguage = .swift

    public init() {}

    public func scoreFile(
        path: String,
        content: String,
        context: QualityScoringContext
    ) async -> QualityAssessment {
        let lines = content.components(separatedBy: .newlines)
        let symbols = await loadSymbols(path: path, content: content)
        let partitions = partitionSymbols(symbols)
        let children = await buildAssessmentChildren(
            typeSymbols: partitions.typeSymbols,
            functionSymbols: partitions.functionSymbols,
            lines: lines
        )
        return buildFileAssessment(path: path, children: children)
    }

    private func buildAssessmentChildren(
        typeSymbols: [Symbol],
        functionSymbols: [Symbol],
        lines: [String]
    ) async -> [QualityAssessment] {
        let children = buildTypeAssessments(
            typeSymbols: typeSymbols,
            functionSymbols: functionSymbols,
            lines: lines
        )
        return children.isEmpty ? [scoreStandaloneFile(lines: lines)] : children
    }

    private func loadSymbols(path: String, content: String) async -> [Symbol] {
        let resourceId = URL(fileURLWithPath: path).absoluteString
        guard let module = await LanguageModuleManager.shared.getModule(for: .swift) else {
            return []
        }
        return module.symbolExtractor.extractSymbols(content: content, resourceId: resourceId)
    }

    private struct SymbolPartitions {
        let typeSymbols: [Symbol]
        let functionSymbols: [Symbol]
    }

    private func partitionSymbols(_ symbols: [Symbol]) -> SymbolPartitions {
        let typeKinds: Set<SymbolKind> = [
            .class, .struct, .enum, .protocol, .extension
        ]
        let functionKinds: Set<SymbolKind> = [
            .function, .initializer
        ]

        let typeSymbols = symbols
            .filter { typeKinds.contains($0.kind) }
            .sorted { $0.lineStart < $1.lineStart }

        let functionSymbols = symbols
            .filter { functionKinds.contains($0.kind) }
            .sorted { $0.lineStart < $1.lineStart }

        return SymbolPartitions(typeSymbols: typeSymbols, functionSymbols: functionSymbols)
    }

    private func buildTypeAssessments(
        typeSymbols: [Symbol],
        functionSymbols: [Symbol],
        lines: [String]
    ) -> [QualityAssessment] {
        guard !typeSymbols.isEmpty else {
            return []
        }

        return typeSymbols.enumerated().map { idx, typeSymbol in
            let typeRange = inferTypeRange(index: idx, typeSymbols: typeSymbols, linesCount: lines.count)
            return scoreType(
                typeSymbol: typeSymbol,
                typeRange: typeRange,
                functionSymbols: functionSymbols,
                lines: lines
            )
        }
    }

    private func inferTypeRange(index: Int, typeSymbols: [Symbol], linesCount: Int) -> (start: Int, end: Int) {
        let start = typeSymbols[index].lineStart
        if index + 1 < typeSymbols.count {
            return (start, max(start, typeSymbols[index + 1].lineStart - 1))
        }
        return (start, linesCount)
    }

    private func scoreType(
        typeSymbol: Symbol,
        typeRange: (start: Int, end: Int),
        functionSymbols: [Symbol],
        lines: [String]
    ) -> QualityAssessment {
        let methodsInType = functionSymbols.filter {
            $0.lineStart >= typeRange.start && $0.lineStart <= typeRange.end
        }

        let methodAssessments = methodsInType.map { method in
            scoreMethodSymbol(method, lines: lines)
        }

        let typeIssues = methodAssessments.flatMap(\.issues)
        let typeScore = aggregate(parentName: typeSymbol.name, children: methodAssessments, kind: .type)
        let typeBreakdown = QualityBreakdown(
            categoryScores: typeScore.breakdown.categoryScores,
            metrics: typeScore.breakdown.metrics
        )

        return QualityAssessment(
            entityType: .type,
            entityName: typeSymbol.name,
            language: .swift,
            score: typeScore.score,
            breakdown: typeBreakdown,
            issues: typeIssues,
            children: methodAssessments
        )
    }

    private func scoreMethodSymbol(_ method: Symbol, lines: [String]) -> QualityAssessment {
        let methodRange = inferBraceRange(lines: lines, startLine: method.lineStart)
        let methodStart = method.lineStart
        let methodEnd = methodRange?.endLine ?? method.lineStart

        let methodLines = slice(lines: lines, start: methodStart, end: methodEnd)
        let methodName = method.kind == .initializer ? "init" : method.name
        return scoreMethod(name: methodName, startLine: methodStart, endLine: methodEnd, lines: methodLines)
    }

    private func buildFileAssessment(path: String, children: [QualityAssessment]) -> QualityAssessment {
        let fileAggregate = aggregate(parentName: path, children: children, kind: .file)

        var fileIssues: [QualityIssue] = []
        if fileAggregate.score <= 0 {
            fileIssues.append(
                QualityIssue(
                    severity: .critical,
                    category: .maintainability,
                    message: "File score computed as 0; scorer malfunction"
                )
            )
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

    private func scoreMethod(name: String, startLine: Int, endLine: Int, lines: [String]) -> QualityAssessment {
        let metrics = methodMetrics(lines: lines)
        var score = 92.0
        var issues: [QualityIssue] = []

        applyLOCHeuristics(loc: metrics.loc, startLine: startLine, score: &score, issues: &issues)
        applyNestingHeuristics(nesting: metrics.nesting, startLine: startLine, score: &score, issues: &issues)
        applyTodoHeuristics(hasTodo: metrics.hasTodo, startLine: startLine, score: &score, issues: &issues)
        applyBranchHeuristics(branches: metrics.branches, startLine: startLine, score: &score, issues: &issues)

        let breakdown = makeMethodBreakdown(
            loc: metrics.loc,
            nesting: metrics.nesting,
            branches: metrics.branches,
            score: score,
            startLine: startLine,
            endLine: endLine
        )

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

    private struct MethodMetrics {
        let loc: Int
        let nesting: Int
        let branches: Int
        let hasTodo: Bool
    }

    private func methodMetrics(lines: [String]) -> MethodMetrics {
        let loc = nonEmptyLineCount(lines)
        let nesting = maxBraceNesting(lines)
        let hasTodo = lines.contains {
            $0.localizedCaseInsensitiveContains("TODO") ||
                $0.localizedCaseInsensitiveContains("FIXME")
        }
        let switchCount = lines.filter { $0.contains("switch ") }.count
        let ifCount = lines.filter { $0.contains("if ") }.count
        let guardCount = lines.filter { $0.contains("guard ") }.count
        return MethodMetrics(loc: loc, nesting: nesting, branches: switchCount + ifCount + guardCount, hasTodo: hasTodo)
    }

    private func applyLOCHeuristics(loc: Int, startLine: Int, score: inout Double, issues: inout [QualityIssue]) {
        if loc > 80 {
            score -= 35
            issues.append(QualityIssue(
                severity: .warning,
                category: .complexity,
                message: "Long method (\(loc) non-empty lines)",
                line: startLine
            ))
            return
        }

        if loc > 40 {
            score -= 18
            issues.append(QualityIssue(
                severity: .info,
                category: .complexity,
                message: "Moderately long method (\(loc) non-empty lines)",
                line: startLine
            ))
        }
    }

    private func applyNestingHeuristics(
        nesting: Int,
        startLine: Int,
        score: inout Double,
        issues: inout [QualityIssue]
    ) {
        if nesting >= 5 {
            score -= 20
            issues.append(QualityIssue(
                severity: .warning,
                category: .complexity,
                message: "Deep nesting (max nesting \(nesting))",
                line: startLine
            ))
            return
        }

        if nesting >= 3 {
            score -= 10
            issues.append(QualityIssue(
                severity: .info,
                category: .complexity,
                message: "Nesting depth \(nesting)",
                line: startLine
            ))
        }
    }

    private func applyTodoHeuristics(hasTodo: Bool, startLine: Int, score: inout Double, issues: inout [QualityIssue]) {
        guard hasTodo else {
            return
        }

        score -= 5
        issues.append(QualityIssue(
            severity: .info,
            category: .maintainability,
            message: "Contains TODO/FIXME",
            line: startLine
        ))
    }

    private func applyBranchHeuristics(branches: Int, startLine: Int, score: inout Double, issues: inout [QualityIssue]) {
        guard branches > 12 else {
            return
        }

        score -= 15
        issues.append(QualityIssue(
            severity: .warning,
            category: .complexity,
            message: "Many branches (\(branches))",
            line: startLine
        ))
    }

    private func makeMethodBreakdown(
        loc: Int,
        nesting: Int,
        branches: Int,
        score: Double,
        startLine: Int,
        endLine: Int
    ) -> QualityBreakdown {
        let categoryScores: [QualityCategory: Double] = [
            .readability: clamp(100 - Double(loc) * 0.5 - Double(nesting) * 3),
            .complexity: clamp(100 - Double(loc) * 0.8 - Double(nesting) * 6 - Double(branches) * 1.2),
            .maintainability: clamp(score),
            .correctness: clamp(85),
            .architecture: clamp(80)
        ]

        return QualityBreakdown(categoryScores: categoryScores, metrics: [
            "loc": Double(loc),
            "nesting": Double(nesting),
            "branches": Double(branches),
            "startLine": Double(startLine),
            "endLine": Double(endLine)
        ])
    }

    private enum AggregateKind {
        case file
        case type
    }

    private func aggregate(
        parentName: String,
        children: [QualityAssessment],
        kind: AggregateKind
    ) -> QualityAssessment {
        guard !children.isEmpty else {
            let breakdown = QualityBreakdown(categoryScores: [
                .readability: 50,
                .complexity: 50,
                .maintainability: 50,
                .correctness: 50,
                .architecture: 50
            ])
            let entityType: QualityEntityType = (kind == .file) ? .file : .type
            return QualityAssessment(
                entityType: entityType,
                entityName: parentName,
                language: .swift,
                score: 50,
                breakdown: breakdown
            )
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

        score = clamp(score * 0.85 + minScore * 0.15)

        var merged: [String: Double] = [:]
        for child in children {
            for (category, categoryScore) in child.breakdown.categoryScores {
                merged[category, default: 0] += categoryScore
            }
        }
        for (category, categoryScore) in merged {
            merged[category] = categoryScore / Double(children.count)
        }

        let breakdown = QualityBreakdown(categoryScores: merged, metrics: [
            "children": Double(children.count),
            "avg": avg,
            "min": minScore
        ])

        let entityType: QualityEntityType = (kind == .file) ? .file : .type
        return QualityAssessment(
            entityType: entityType,
            entityName: parentName,
            language: .swift,
            score: score,
            breakdown: breakdown
        )
    }
}

extension SwiftHeuristicScorer {
    private func scoreStandaloneFile(lines: [String]) -> QualityAssessment {
        let loc = nonEmptyLineCount(lines)
        var score = 80.0
        var issues: [QualityIssue] = []

        if loc > 800 {
            score -= 30
            issues.append(
                QualityIssue(
                    severity: .warning,
                    category: .maintainability,
                    message: "Large file (\(loc) non-empty lines)"
                )
            )
        } else if loc > 400 {
            score -= 15
            issues.append(
                QualityIssue(
                    severity: .info,
                    category: .maintainability,
                    message: "Moderately large file (\(loc) non-empty lines)"
                )
            )
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

    private func slice(lines: [String], start: Int, end: Int) -> [String] {
        if lines.isEmpty { return [] }
        let startIndex = max(1, start)
        let endIndex = min(end, lines.count)
        if startIndex > endIndex { return [] }
        return Array(lines[(startIndex - 1)...(endIndex - 1)])
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
        guard startLine >= 1, startLine <= lines.count else {
            return nil
        }

        var state = BraceScanState()
        let startIndex = startLine - 1

        for idx in startIndex..<lines.count {
            scanLineForBraces(lines[idx], state: &state)
            if let endLine = resolvedEndLineIfComplete(state: state, currentIndex: idx) {
                return BraceRange(endLine: endLine)
            }
            if shouldStopScan(state: state, startIndex: startIndex, currentIndex: idx) {
                return BraceRange(endLine: idx + 1)
            }
        }

        return nil
    }

    private struct BraceScanState {
        var depth: Int = 0
        var started: Bool = false
    }

    private func scanLineForBraces(_ line: String, state: inout BraceScanState) {
        for ch in line {
            if ch == "{" {
                state.depth += 1
                state.started = true
                continue
            }

            if ch == "}" {
                handleClosingBrace(state: &state)
            }
        }
    }

    private func handleClosingBrace(state: inout BraceScanState) {
        guard state.started else {
            return
        }

        state.depth = max(0, state.depth - 1)
    }

    private func resolvedEndLineIfComplete(state: BraceScanState, currentIndex: Int) -> Int? {
        guard state.started, state.depth == 0 else {
            return nil
        }

        return currentIndex + 1
    }

    private func shouldStopScan(state: BraceScanState, startIndex: Int, currentIndex: Int) -> Bool {
        state.started && currentIndex - startIndex > 600
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}
