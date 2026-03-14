import Foundation
import SQLite3

final class DatabaseCodeChunkManager {
    private unowned let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func replaceCodeChunks(
        resourceId: String,
        modelId: String,
        chunks: [CodeChunkRecord]
    ) throws {
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
    }

    func deleteCodeChunks(resourceId: String, modelId: String? = nil) throws {
        if let modelId {
            try database.execute(
                sql: "DELETE FROM code_chunks WHERE resource_id = ? AND model_id = ?;",
                parameters: [resourceId, modelId]
            )
            return
        }

        try database.execute(
            sql: "DELETE FROM code_chunks WHERE resource_id = ?;",
            parameters: [resourceId]
        )
    }

    func searchSimilarCodeChunks(
        modelId: String,
        queryVector: [Float],
        limit: Int
    ) throws -> [CodeChunkSimilarityResult] {
        guard !queryVector.isEmpty else { return [] }
        let normalizedQuery = normalize(queryVector)
        guard !normalizedQuery.isEmpty else { return [] }

        let sql = """
        SELECT r.path, c.line_start, c.line_end, c.snippet, c.vector_blob
        FROM code_chunks c
        INNER JOIN resources r ON r.id = c.resource_id
        WHERE c.model_id = ?;
        """

        let matches = try database.withPreparedStatement(sql: sql, parameters: [modelId]) { statement in
            var results: [CodeChunkSimilarityResult] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let filePath = String(cString: sqlite3_column_text(statement, 0))
                let lineStart = Int(sqlite3_column_int(statement, 1))
                let lineEnd = Int(sqlite3_column_int(statement, 2))
                let snippet = String(cString: sqlite3_column_text(statement, 3))

                guard let blobPointer = sqlite3_column_blob(statement, 4) else { continue }
                let blobLength = Int(sqlite3_column_bytes(statement, 4))
                let embeddingData = Data(bytes: blobPointer, count: blobLength)
                guard let storedVector = decodeVector(from: embeddingData) else { continue }
                let normalizedVector = normalize(storedVector)
                guard !normalizedVector.isEmpty else { continue }

                let similarity = cosineSimilarity(lhs: normalizedQuery, rhs: normalizedVector)
                results.append(
                    CodeChunkSimilarityResult(
                        filePath: filePath,
                        lineStart: lineStart,
                        lineEnd: lineEnd,
                        snippet: snippet,
                        similarityScore: similarity
                    )
                )
            }
            return results
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.similarityScore == rhs.similarityScore {
                    if lhs.filePath == rhs.filePath {
                        return lhs.lineStart < rhs.lineStart
                    }
                    return lhs.filePath < rhs.filePath
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

struct CodeChunkRecord: Sendable {
    let chunkIndex: Int
    let lineStart: Int
    let lineEnd: Int
    let snippet: String
    let vector: [Float]
}
