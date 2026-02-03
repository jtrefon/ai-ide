import Foundation

extension CodebaseIndex {
    public func runAIEnrichment() {
        guard isEnabled else {
            Task { @MainActor in await IndexLogger.shared.log("AI Enrichment skipped: Indexing is disabled") }
            return
        }

        aiEnrichmentTask?.cancel()
        aiEnrichmentTask = Task { @MainActor in
            let scoringEngine = QualityScoringEngine(projectRoot: projectRoot, scorers: [SwiftHeuristicScorer()])
            let start = Date()

            await announceEnrichmentStart()

            let files = aiEnrichmentFiles()
            let total = files.count
            await IndexLogger.shared.log("Found \(total) files for AI enrichment")

            let processed = await processEnrichmentFiles(files, total: total, scoringEngine: scoringEngine)

            if Task.isCancelled { return }
            await finishEnrichment(start: start, processed: processed)
        }
    }

    private func announceEnrichmentStart() async {
        await IndexLogger.shared.log("AI Enrichment started")
        await eventBus.publish(AIEnrichmentStartedEvent())
    }

    private func processEnrichmentFiles(
        _ files: [URL],
        total: Int,
        scoringEngine: QualityScoringEngine
    ) async -> Int {
        var processed = 0
        for file in files {
            if Task.isCancelled { break }
            if !isEnabled {
                await IndexLogger.shared.log("AI Enrichment aborted: Indexing disabled during process")
                break
            }

            await logEnrichmentProgress(processed: processed, total: total, file: file)

            if await shouldSkipAIEnrichment(for: file) {
                await IndexLogger.shared.log("Skipping \(file.lastPathComponent) (already enriched)")
                processed += 1
                await publishEnrichmentProgress(processed: processed, total: total, file: file)
                continue
            }

            await enrichFileForAI(file, scoringEngine: scoringEngine)

            processed += 1
            await publishEnrichmentProgress(processed: processed, total: total, file: file)
        }
        return processed
    }

    private func logEnrichmentProgress(processed: Int, total: Int, file: URL) async {
        await IndexLogger.shared.log("Enriching file \(processed + 1)/\(total): \(file.lastPathComponent)")
        await publishEnrichmentProgress(processed: processed, total: total, file: file)
    }

    private func publishEnrichmentProgress(processed: Int, total: Int, file: URL) async {
        await eventBus.publish(
            AIEnrichmentProgressEvent(
                processedCount: processed,
                totalCount: total,
                currentFile: file
            )
        )
    }

    private func finishEnrichment(start: Date, processed: Int) async {
        let duration = Date().timeIntervalSince(start)
        let formattedDuration = String(format: "%.2f", duration)
        await IndexLogger.shared.log("AI Enrichment completed in \(formattedDuration)s")
        await eventBus.publish(AIEnrichmentCompletedEvent(processedCount: processed, duration: duration))
    }

    private func aiEnrichmentFiles() -> [URL] {
        IndexFileEnumerator
            .enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns)
            .filter { Self.isAIEnrichableFile($0) }
    }

    private func shouldSkipAIEnrichment(for file: URL) async -> Bool {
        let fileModTime = (try? file.resourceValues(
            forKeys: [.contentModificationDateKey]
        ))?.contentModificationDate?.timeIntervalSince1970
        let existingModTime = try? await database.getResourceLastModified(resourceId: file.absoluteString)

        guard let fileModTime else { return false }
        guard let existingModTime else { return false }
        guard abs(existingModTime - fileModTime) < 0.000_001 else { return false }
        return (try? await database.isResourceAIEnriched(resourceId: file.absoluteString)) == true
    }

    private func enrichFileForAI(_ file: URL, scoringEngine: QualityScoringEngine) async {
        do {
            let content = try String(contentsOf: file, encoding: .utf8)
            let relPath = makeRelativePath(file)

            let assessment = await scoringEngine.score(
                language: LanguageDetector.detect(at: file),
                path: relPath,
                content: content
            )
            let heuristicScore = max(0, min(100, assessment.score))
            await persistHeuristicQuality(heuristicScore, assessment: assessment, file: file, relPath: relPath)

            let response = try await withTimeout(seconds: 45) {
                try await self.aiService.sendMessage(AIServiceMessageWithProjectRootRequest(
                    message: Self.makeEnrichmentPrompt(path: file.path, content: content),
                    context: nil,
                    tools: nil,
                    mode: nil,
                    projectRoot: self.projectRoot
                ))
            }

            let result = Self.parseEnrichmentResponse(from: response.content)
            let score = result?.score ?? 0
            let summary = result?.summary
            await IndexLogger.shared.log("IndexerActor: AI suggested score \(score) for \(file.lastPathComponent)")

            try await database.markAIEnriched(resourceId: file.absoluteString, score: Double(score), summary: summary)
            await IndexLogger.shared.log("Successfully enriched \(file.lastPathComponent) (Score: \(score))")
        } catch {
            await CrashReporter.shared.capture(
                error,
                context: CrashReportContext(operation: "CodebaseIndex.enrichFileForAI"),
                metadata: ["file": file.path],
                file: #fileID,
                function: #function,
                line: #line
            )
            await IndexLogger.shared.log("Failed to enrich \(file.lastPathComponent): \(error)")
        }
    }

    private func makeRelativePath(_ file: URL) -> String {
        if file.path.hasPrefix(self.projectRoot.path + "/") {
            return String(file.path.dropFirst(self.projectRoot.path.count + 1))
        }
        return file.path
    }

    private func persistHeuristicQuality(
        _ score: Double,
        assessment: QualityAssessment,
        file: URL,
        relPath: String
    ) async {
        do {
            let jsonData = try JSONEncoder().encode(assessment)
            let json = String(data: jsonData, encoding: .utf8)
            try await database.updateQualityScore(resourceId: file.absoluteString, score: score)
            try await database.updateQualityDetails(resourceId: file.absoluteString, details: json)
            let formattedScore = String(format: "%.0f", score)
            await IndexLogger.shared.log("QualityScore: \(formattedScore) for \(relPath)")
        } catch {
            await IndexLogger.shared.log("QualityScore: Failed to persist quality details for \(relPath): \(error)")
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AppError.aiServiceError("AI request timed out after \(seconds)s")
            }

            guard let result = try await group.next() else {
                throw AppError.aiServiceError("Task group returned no result")
            }
            group.cancelAll()
            return result
        }
    }
}
