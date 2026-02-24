import Foundation
import SQLite3

final class DatabaseMemoryManager {
    private unowned let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func saveMemory(_ memory: MemoryEntry) throws {
        let sql = """
        INSERT INTO memories (id, tier, content, category, timestamp, protection_level)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            tier = excluded.tier,
            content = excluded.content,
            category = excluded.category,
            timestamp = excluded.timestamp,
            protection_level = excluded.protection_level;
        """

        try database.execute(sql: sql, parameters: [
            memory.id,
            memory.tier.rawValue,
            memory.content,
            memory.category,
            memory.timestamp.timeIntervalSince1970,
            memory.protectionLevel
        ])
    }

    func getMemories(tier: MemoryTier? = nil) throws -> [MemoryEntry] {
        var sql = "SELECT id, tier, content, category, timestamp, protection_level FROM memories"
        var parameters: [Any] = []
        if let tier {
            sql += " WHERE tier = ?"
            parameters.append(tier.rawValue)
        }
        sql += " ORDER BY timestamp DESC;"

        return try database.withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var memories: [MemoryEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let tierStr = String(cString: sqlite3_column_text(statement, 1))
                let content = String(cString: sqlite3_column_text(statement, 2))
                let category = String(cString: sqlite3_column_text(statement, 3))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let protectionLevel = Int(sqlite3_column_int(statement, 5))

                if let parsedTier = MemoryTier(rawValue: tierStr) {
                    memories.append(
                        MemoryEntry(
                            id: id,
                            tier: parsedTier,
                            content: content,
                            category: category,
                            timestamp: timestamp,
                            protectionLevel: protectionLevel
                        )
                    )
                }
            }
            return memories
        }
    }

    func deleteMemory(id: String) throws {
        let sql = "DELETE FROM memories WHERE id = ?;"
        try database.execute(sql: sql, parameters: [id])
    }

    func saveMemoryEmbedding(memoryId: String, modelId: String, vector: [Float]) throws {
        guard !vector.isEmpty else { return }

        let data = vector.withUnsafeBufferPointer { buffer in
            Data(buffer: UnsafeBufferPointer(start: UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self), count: buffer.count * MemoryLayout<Float>.size))
        }

        let sql = """
        INSERT INTO memory_embeddings (memory_id, model_id, dimensions, vector_blob, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(memory_id, model_id) DO UPDATE SET
            dimensions = excluded.dimensions,
            vector_blob = excluded.vector_blob,
            updated_at = excluded.updated_at;
        """

        try database.execute(sql: sql, parameters: [
            memoryId,
            modelId,
            vector.count,
            data,
            Date().timeIntervalSince1970
        ])
    }

    func searchSimilarMemories(
        modelId: String,
        queryVector: [Float],
        limit: Int,
        tier: MemoryTier?
    ) throws -> [MemorySimilarityResult] {
        guard !queryVector.isEmpty else { return [] }
        let normalizedQuery = normalize(queryVector)
        guard !normalizedQuery.isEmpty else { return [] }

        var sql = """
        SELECT m.id, m.tier, m.content, m.category, m.timestamp, m.protection_level, e.vector_blob
        FROM memory_embeddings e
        INNER JOIN memories m ON m.id = e.memory_id
        WHERE e.model_id = ?
        """

        var parameters: [Any] = [modelId]
        if let tier {
            sql += " AND m.tier = ?"
            parameters.append(tier.rawValue)
        }
        sql += ";"

        let matches = try database.withPreparedStatement(sql: sql, parameters: parameters) { statement in
            var results: [MemorySimilarityResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let memoryId = String(cString: sqlite3_column_text(statement, 0))
                let tierRaw = String(cString: sqlite3_column_text(statement, 1))
                let content = String(cString: sqlite3_column_text(statement, 2))
                let category = String(cString: sqlite3_column_text(statement, 3))
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let protectionLevel = Int(sqlite3_column_int(statement, 5))

                guard let blobPointer = sqlite3_column_blob(statement, 6) else { continue }
                let blobLength = Int(sqlite3_column_bytes(statement, 6))
                let embeddingData = Data(bytes: blobPointer, count: blobLength)
                guard let memoryVector = decodeVector(from: embeddingData) else { continue }
                let normalizedMemoryVector = normalize(memoryVector)
                guard !normalizedMemoryVector.isEmpty else { continue }

                let similarity = cosineSimilarity(lhs: normalizedQuery, rhs: normalizedMemoryVector)
                guard let parsedTier = MemoryTier(rawValue: tierRaw) else { continue }

                let entry = MemoryEntry(
                    id: memoryId,
                    tier: parsedTier,
                    content: content,
                    category: category,
                    timestamp: timestamp,
                    protectionLevel: protectionLevel
                )

                results.append(MemorySimilarityResult(entry: entry, similarityScore: similarity))
            }
            return results
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.similarityScore == rhs.similarityScore {
                    return lhs.entry.timestamp > rhs.entry.timestamp
                }
                return lhs.similarityScore > rhs.similarityScore
            }
            .prefix(max(1, limit))
            .map { $0 }
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

    private func normalize(_ vector: [Float]) -> [Float] {
        let sumSquares = vector.reduce(Float(0)) { partial, value in
            partial + (value * value)
        }
        guard sumSquares > 0 else { return [] }

        let norm = sqrt(sumSquares)
        return vector.map { $0 / norm }
    }

    private func cosineSimilarity(lhs: [Float], rhs: [Float]) -> Double {
        guard lhs.count == rhs.count else { return -1.0 }
        let score = zip(lhs, rhs).reduce(Float(0)) { partial, pair in
            partial + (pair.0 * pair.1)
        }
        return Double(score)
    }
}
