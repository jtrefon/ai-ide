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
}
