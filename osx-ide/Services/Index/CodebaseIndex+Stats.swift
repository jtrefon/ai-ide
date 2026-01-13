import Foundation

extension CodebaseIndex {
    public func getStats() async throws -> IndexStats {
        let counts = try await database.getIndexStatsCounts()
        let totalProjectFileCount = IndexFileEnumerator.enumerateProjectFiles(
                    rootURL: projectRoot, 
                    excludePatterns: excludePatterns
                ).count

        let aiEnrichableProjectFileCount = IndexFileEnumerator
            .enumerateProjectFiles(rootURL: projectRoot, excludePatterns: excludePatterns)
            .filter { Self.isAIEnrichableFile($0) }
            .count

        let scoped = await loadScopedStats(fallbackIndexedCount: counts.indexedResourceCount)
        let kindCounts = try await database.getSymbolKindCounts()
        let avgQuality = try await database.getAverageQualityScore()
        let metadata = databaseMetadata()
        let kindStats = symbolKindStats(kindCounts)

        return IndexStats(
            indexedResourceCount: scoped.indexedCount,
            aiEnrichedResourceCount: scoped.aiEnrichedCount,
            aiEnrichableProjectFileCount: aiEnrichableProjectFileCount,
            totalProjectFileCount: totalProjectFileCount,
            symbolCount: counts.symbolCount,
            classCount: kindStats.classCount,
            structCount: kindStats.structCount,
            enumCount: kindStats.enumCount,
            protocolCount: kindStats.protocolCount,
            functionCount: kindStats.functionCount,
            variableCount: kindStats.variableCount,
            memoryCount: counts.memoryCount,
            longTermMemoryCount: counts.longTermMemoryCount,
            databaseSizeBytes: metadata.sizeBytes,
            databasePath: dbPath,
            isDatabaseInWorkspace: metadata.isInWorkspace,
            averageQualityScore: avgQuality,
            averageAIQualityScore: scoped.avgAIQuality
        )
    }

    private func loadScopedStats(
            fallbackIndexedCount: Int
        ) async -> (indexedCount: Int, aiEnrichedCount: Int, avgAIQuality: Double) {
        let allowed = AppConstants.Indexing.allowedExtensions
        let indexedCount = (try? await database.getIndexedResourceCountScoped(
            projectRoot: projectRoot,
            allowedExtensions: allowed
        )) ?? fallbackIndexedCount
        let aiEnrichedCount = (try? await database.getAIEnrichedResourceCountScoped(
                    projectRoot: projectRoot, 
                    allowedExtensions: allowed
                )) ?? 0
        let avgAIQuality = (try? await database.getAverageAIQualityScoreScoped(
                    projectRoot: projectRoot, 
                    allowedExtensions: allowed
                )) ?? 0
        return (indexedCount, aiEnrichedCount, avgAIQuality)
    }

    private func databaseMetadata() -> (sizeBytes: Int64, isInWorkspace: Bool) {
        let sizeBytes: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: dbPath)
            sizeBytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            sizeBytes = 0
        }

        let workspaceIndexDir = projectRoot.appendingPathComponent(".ide").appendingPathComponent("index")
        let dbURL = URL(fileURLWithPath: dbPath)
        let isInWorkspace = dbURL.path.hasPrefix(workspaceIndexDir.path)

        return (sizeBytes, isInWorkspace)
    }

    private func symbolKindStats(
        _ kindCounts: [String: Int]
    ) -> (classCount: Int, structCount: Int, enumCount: Int, protocolCount: Int, functionCount: Int, variableCount: Int) {
        return (
            classCount: kindCounts[SymbolKind.class.rawValue] ?? 0,
            structCount: kindCounts[SymbolKind.struct.rawValue] ?? 0,
            enumCount: kindCounts[SymbolKind.enum.rawValue] ?? 0,
            protocolCount: kindCounts[SymbolKind.protocol.rawValue] ?? 0,
            functionCount: kindCounts[SymbolKind.function.rawValue] ?? 0,
            variableCount: kindCounts[SymbolKind.variable.rawValue] ?? 0
        )
    }
}
