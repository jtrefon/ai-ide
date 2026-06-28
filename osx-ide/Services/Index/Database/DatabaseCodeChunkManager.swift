import Foundation
import SQLite3

final class DatabaseCodeChunkManager {
    private unowned let database: DatabaseManager
    private var hnswIndices: [String: HNSWIndex] = [:]
    private var modelIdsNeedingRebuild: Set<String> = []

    private func chunkKey(resourceId: String, chunkIndex: Int) -> String {
        "\(resourceId):\(chunkIndex)"
    }

    init(database: DatabaseManager) {
        self.database = database
    }

    func markIndexDirty(modelId: String) {
        modelIdsNeedingRebuild.insert(modelId)
    }

    func replaceCodeChunks(
        resourceId: String,
        modelId: String,
        chunks: [CodeChunkRecord]
    ) throws {
        let oldKeys = try findChunkKeys(resourceId: resourceId, modelId: modelId)
        for key in oldKeys {
            hnswIndices[modelId]?.remove(id: key)
        }

        try deleteCodeChunks(resourceId: resourceId, modelId: modelId)
        guard !chunks.isEmpty else { return }

        let sql = """
        INSERT INTO code_chunks (
            resource_id,
            model_id,
            chunk_index,
            line_start,
            line_end,
            snippet,
            dimensions,
            vector_blob,
            updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        let updatedAt = Date().timeIntervalSince1970
        for chunk in chunks {
            let vectorData = chunk.vector.withUnsafeBufferPointer { buffer in
                Data(
                    buffer: UnsafeBufferPointer(
                        start: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self),
                        count: buffer.count * MemoryLayout<Float>.size
                    )
                )
            }

            try database.execute(sql: sql, parameters: [
                resourceId,
                modelId,
                chunk.chunkIndex,
                chunk.lineStart,
                chunk.lineEnd,
                chunk.snippet,
                chunk.vector.count,
                vectorData,
                updatedAt
            ])
        }

        for chunk in chunks {
            let key = chunkKey(resourceId: resourceId, chunkIndex: chunk.chunkIndex)
            hnswIndices[modelId]?.insert(id: key, vector: chunk.vector)
        }
    }

    func deleteCodeChunks(resourceId: String, modelId: String? = nil) throws {
        if let modelId {
            let oldKeys = try findChunkKeys(resourceId: resourceId, modelId: modelId)
            for key in oldKeys {
                hnswIndices[modelId]?.remove(id: key)
            }
            try database.execute(
                sql: "DELETE FROM code_chunks WHERE resource_id = ? AND model_id = ?;",
                parameters: [resourceId, modelId]
            )
            return
        }

        for (mid, _) in hnswIndices {
            let oldKeys = try findChunkKeys(resourceId: resourceId, modelId: mid)
            for key in oldKeys {
                hnswIndices[mid]?.remove(id: key)
            }
        }

        try database.execute(
            sql: "DELETE FROM code_chunks WHERE resource_id = ?;",
            parameters: [resourceId]
        )
    }

    private func findChunkKeys(resourceId: String, modelId: String) throws -> [String] {
        let sql = "SELECT chunk_index FROM code_chunks WHERE resource_id = ? AND model_id = ?;"
        return try database.withPreparedStatement(sql: sql, parameters: [resourceId, modelId]) { statement in
            var keys: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let index = Int(sqlite3_column_int(statement, 0))
                keys.append(chunkKey(resourceId: resourceId, chunkIndex: index))
            }
            return keys
        }
    }

    func searchSimilarCodeChunks(
        modelId: String,
        queryVector: [Float],
        limit: Int
    ) throws -> [CodeChunkSimilarityResult] {
        guard !queryVector.isEmpty else { return [] }

        if modelIdsNeedingRebuild.contains(modelId) || hnswIndices[modelId] == nil {
            rebuildHNSWIndex(modelId: modelId)
        }

        let hnswResults = hnswIndices[modelId]?.search(query: queryVector, limit: limit) ?? []

        guard !hnswResults.isEmpty else { return [] }

        return try fetchChunkResults(ids: hnswResults, modelId: modelId)
    }

    private func rebuildHNSWIndex(modelId: String) {
        let index = HNSWIndex()
        defer { modelIdsNeedingRebuild.remove(modelId) }

        let sql = """
        SELECT c.resource_id, c.chunk_index, c.vector_blob
        FROM code_chunks c
        WHERE c.model_id = ?;
        """

        let matches = (try? database.withPreparedStatement(sql: sql, parameters: [modelId]) { statement -> [(String, Int, [Float])]? in
            var rows: [(String, Int, [Float])] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let resourceId = String(cString: sqlite3_column_text(statement, 0))
                let chunkIndex = Int(sqlite3_column_int(statement, 1))
                guard let blobPointer = sqlite3_column_blob(statement, 2) else { continue }
                let blobLength = Int(sqlite3_column_bytes(statement, 2))
                let embeddingData = Data(bytes: blobPointer, count: blobLength)
                guard let vector = decodeVector(from: embeddingData), !vector.isEmpty else { continue }
                rows.append((resourceId, chunkIndex, vector))
            }
            return rows
        }) ?? []; if matches.isEmpty { return }

        for (resourceId, chunkIndex, vector) in matches {
            let key = chunkKey(resourceId: resourceId, chunkIndex: chunkIndex)
            index.insert(id: key, vector: vector)
        }

        hnswIndices[modelId] = index
    }

    private func fetchChunkResults(
        ids: [(id: String, similarity: Float)],
        modelId: String
    ) throws -> [CodeChunkSimilarityResult] {
        guard !ids.isEmpty else { return [] }

        // Parse all keys upfront
        let parsed: [(resourceId: String, chunkIndex: Int, similarity: Float)] = ids.compactMap { entry in
            guard let colonRange = entry.id.range(of: ":") else { return nil }
            let resourceId = String(entry.id[..<colonRange.lowerBound])
            let chunkIndex = Int(entry.id[colonRange.upperBound...]) ?? 0
            return (resourceId, chunkIndex, entry.similarity)
        }
        guard !parsed.isEmpty else { return [] }

        // Build a single query with OR conditions for each (resource_id, chunk_index) pair
        let conditions = parsed.map { _ in "(c.resource_id = ? AND c.chunk_index = ?)" }.joined(separator: " OR ")
        let sql = """
        SELECT r.path, c.line_start, c.line_end, c.snippet, c.resource_id, c.chunk_index
        FROM code_chunks c
        INNER JOIN resources r ON r.id = c.resource_id
        WHERE c.model_id = ? AND (\(conditions));
        """

        var parameters: [Any] = [modelId]
        for entry in parsed {
            parameters.append(entry.resourceId)
            parameters.append(entry.chunkIndex)
        }

        let rows = try database.withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var rows: [(String, Int, Int, String, String, Int)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(statement, 0))
                let ls = Int(sqlite3_column_int(statement, 1))
                let le = Int(sqlite3_column_int(statement, 2))
                let snippet = String(cString: sqlite3_column_text(statement, 3))
                let resId = String(cString: sqlite3_column_text(statement, 4))
                let chunkIdx = Int(sqlite3_column_int(statement, 5))
                rows.append((path, ls, le, snippet, resId, chunkIdx))
            }
            return rows
        }

        // Build a lookup map for fast similarity score joining
        var similarityMap: [String: Float] = [:]
        for entry in parsed {
            similarityMap["\(entry.resourceId):\(entry.chunkIndex)"] = entry.similarity
        }

        let results: [CodeChunkSimilarityResult] = rows.compactMap { row in
            let key = "\(row.4):\(row.5)"
            guard let similarity = similarityMap[key] else { return nil }
            return CodeChunkSimilarityResult(
                filePath: row.0,
                lineStart: row.1,
                lineEnd: row.2,
                snippet: row.3,
                similarityScore: Double(similarity)
            )
        }

        return results.sorted { $0.similarityScore > $1.similarityScore }
    }

    private func decodeVector(from data: Data) -> [Float]? {
        let stride = MemoryLayout<Float>.size
        guard data.count >= stride, data.count % stride == 0 else { return nil }

        let count = data.count / stride
        return data.withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: Float.self)
            return Array(pointer.prefix(count))
        }
    }

  }

struct CodeChunkRecord: Sendable {
    let chunkIndex: Int
    let lineStart: Int
    let lineEnd: Int
    let snippet: String
    let vector: [Float]
}
