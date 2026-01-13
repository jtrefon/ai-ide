import Foundation
import SQLite3

final class DatabaseSchemaManager {
    private unowned let database: DatabaseManager

    init(database: DatabaseManager) {
        self.database = database
    }

    func createTables() throws {
        try createBaseSchema()
        try applyMigrations()
    }

    private func createBaseSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS resources (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            language TEXT NOT NULL,
            last_modified REAL NOT NULL,
            content_hash TEXT,
            quality_score REAL,
            quality_details TEXT
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS resources_fts USING fts5(
            path,
            content,
            content_id UNINDEXED
        );

        CREATE TABLE IF NOT EXISTS symbols (
            id TEXT PRIMARY KEY,
            resource_id TEXT NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            line_start INTEGER NOT NULL,
            line_end INTEGER NOT NULL,
            description TEXT,
            FOREIGN KEY(resource_id) REFERENCES resources(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_resources_path ON resources(path);
        CREATE INDEX IF NOT EXISTS idx_symbols_resource_id ON symbols(resource_id);
        CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);

        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            tier TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT NOT NULL,
            timestamp REAL NOT NULL,
            protection_level INTEGER NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_memories_tier ON memories(tier);
        CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);
        """
        try database.execute(sql: sql)
    }

    private func applyMigrations() throws {
        try ensureColumnExists(table: "resources", column: "content_hash", columnDefinition: "TEXT")
        try ensureColumnExists(table: "resources", column: "quality_score", columnDefinition: "REAL NOT NULL DEFAULT 0")
        try ensureColumnExists(table: "resources", column: "quality_details", columnDefinition: "TEXT")
        try ensureColumnExists(
                    table: "resources", 
                    column: "ai_enriched", 
                    columnDefinition: "INTEGER NOT NULL DEFAULT 0"
                )
        try ensureColumnExists(table: "resources", column: "summary", columnDefinition: "TEXT")
    }

    private func ensureColumnExists(table: String, column: String, columnDefinition: String) throws {
        let sql = "PRAGMA table_info(\(table));"
        var existingColumns = Set<String>()

        try database.syncOnQueue {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database.db, sql, -1, &statement, nil) != SQLITE_OK {
                throw DatabaseError.prepareFailed
            }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(statement, 1) {
                    existingColumns.insert(String(cString: namePtr))
                }
            }
        }

        guard !existingColumns.contains(column) else { return }
        try database.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(columnDefinition);")
    }
}
