# `search_code` — Fast Code Navigation

## 1. Purpose

A single, precise tool for all code navigation questions. No ML, no vectors, no chunks. Pure SQLite with symbols + FTS5. Indexes in seconds.

## 2. Database Schema

File: `{projectRoot}/.osx-ide/codebase.sqlite`

```sql
CREATE TABLE resources (
    id TEXT PRIMARY KEY,
    path TEXT NOT NULL,
    language TEXT NOT NULL,
    last_modified REAL NOT NULL,
    content_hash TEXT,
    quality_score REAL DEFAULT 0.0
);

CREATE VIRTUAL TABLE resources_fts USING fts5(
    path,
    content,
    content_id UNINDEXED
);

CREATE TABLE symbols (
    id TEXT PRIMARY KEY,
    resource_id TEXT NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    line_start INTEGER NOT NULL,
    line_end INTEGER NOT NULL,
    signature TEXT,
    parent_symbol_id TEXT,
    FOREIGN KEY(resource_id) REFERENCES resources(id) ON DELETE CASCADE
);

-- Indices
CREATE INDEX IF NOT EXISTS idx_resources_path ON resources(path);
CREATE INDEX IF NOT EXISTS idx_symbols_resource_id ON symbols(resource_id);
CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind);
```

**Removed tables:** `code_chunks`, `memory_embeddings`, `memories` (moved to project_memory.sqlite).

## 3. Indexing Pipeline

### 3.1 Full Re-Index

```
User triggers "Re-Index" or project opens
  → Walk project files (skip .git, node_modules, etc.)
  → For each file:
    a. Detect language
    b. Read file content
    c. Compute content hash
    d. Upsert into resources table
    e. Upsert into resources_fts (FTS5)
    f. Extract symbols using language parser
    g. Delete old symbols for this resource
    h. Insert new symbols in batches of 250
  → Prune resources not in file system
  → Done

Estimated time for 10K files: 3-8 seconds
```

### 3.2 Incremental Update (on file save)

```
File saved
  → Detect language, read content, compute hash
  → If hash matches existing → skip (no change)
  → Otherwise:
    a. Upsert resource + FTS
    b. Extract symbols
    c. Delete old symbols
    d. Insert new symbols
  → Done

Estimated time per file: < 50 ms
```

### 3.3 Language Parsers

Keep existing parsers (no changes needed):

| Parser | Languages |
|--------|-----------|
| `SwiftParser.swift` | Swift |
| `TypeScriptParser.swift` | TS, TSX |
| `JavaScriptParser.swift` | JS, JSX, MJS, CJS |
| `PythonParser.swift` | Python |
| `RegexLineSymbolParser.swift` | Fallback for other languages |

Each parser extracts:
- Classes, structs, enums, protocols
- Functions, methods
- Variables, properties, constants
- Extensions
- Type aliases
- Protocol conformances (where feasible)

## 4. Query Patterns

### 4.1 Symbol Lookup (most common)

```sql
SELECT r.path, s.name, s.kind, s.line_start, s.line_end, s.signature
FROM symbols s
JOIN resources r ON r.id = s.resource_id
WHERE s.name LIKE '%' || ? || '%'
  AND (? IS NULL OR s.kind = ?)
ORDER BY
  CASE WHEN s.name = ? THEN 0
       WHEN s.name LIKE ? || '%' THEN 1
       ELSE 2
  END,
  s.name
LIMIT ?;
```

### 4.2 Full-Text Search

```sql
SELECT r.path, snippet(resources_fts, 1, '<b>', '</b>', '...', 32)
FROM resources_fts
JOIN resources r ON r.id = resources_fts.content_id
WHERE resources_fts MATCH ?
LIMIT ?;
```

### 4.3 File Listing (replaces `list_files`)

```sql
SELECT path, language
FROM resources
WHERE (? IS NULL OR path LIKE '%' || ? || '%')
ORDER BY path
LIMIT ? OFFSET ?;
```

### 4.4 Symbols in a File

```sql
SELECT name, kind, line_start, line_end, signature
FROM symbols
WHERE resource_id = (
    SELECT id FROM resources WHERE path = ?
)
ORDER BY line_start;
```

## 5. Tool Definition

See [TOOL_CONTRACTS.md](TOOL_CONTRACTS.md) for the exact JSON schema.

The `search_code` tool receives:
- `query: string` — search term (class name, function name, file name, text pattern)
- `kind?: string` — optional filter: "class" | "function" | "method" | "variable" | etc.
- `path?: string` — optional scope to subdirectory
- `max_results?: int` — default 30, max 100

Returns:
```json
{
  "results": [
    {
      "file": "Sources/App/Services/DataManager.swift",
      "line": 42,
      "kind": "class",
      "name": "DataManager",
      "signature": "class DataManager: ObservableObject",
      "context": "class DataManager: ObservableObject { ... }"
    }
  ],
  "total": 1,
  "cache_hit": false
}
```

## 6. Edge Cases

| Case | Behavior |
|------|----------|
| No results | Return "No matches found for 'query'." |
| Too many results | Return top `max_results` with `total` count |
| Empty query | Return error: "query is required" |
| Invalid kind filter | Ignore filter, search all kinds |
| Path is outside project | Scope to project root |
| Database not yet indexed | Return "Index is still building, please wait" |
| File deleted between index and query | Stale results OK (next re-index cleans up) |

## 7. Files to Create

| File | Contents |
|------|----------|
| `Services/Search/SearchIndexer.swift` | Wraps existing IndexerActor, removes vector paths |
| `Services/Search/SearchQueryEngine.swift` | SQL query methods: searchByName, searchByText, listFiles, symbolsInFile |
| `Services/Search/SearchCodeTool.swift` | AITool protocol conformance for search_code |
| `Services/Search/SearchCodeTool+v2.swift` | ToolDefinition conformance for search_code (if using new system) |

## 8. Files to Modify

| File | Change |
|------|--------|
| `Services/Index/Database/DatabaseSchemaManager.swift` | Remove `code_chunks`, `memory_embeddings` table creation |
| `Services/Index/Indexing/IndexerActor.swift` | Remove `updateCodeChunks` call in `upsertResourceAndIndexSymbols` |
| `Services/Index/Database/DatabaseStore.swift` | Remove `replaceCodeChunks`, `deleteCodeChunks`, `searchSimilarCodeChunks` |
| `Services/Index/CodebaseIndex+SymbolsAndMemories.swift` | Remove embedding-related extensions |
| `Services/ConversationToolProvider.swift` | Replace old search tools with `SearchCodeTool` |

## 9. Files to Delete

| File | Reason |
|------|--------|
| `Services/Index/Database/DatabaseCodeChunkManager.swift` | No more code chunks |
| `Services/Index/Search/HNSWIndex.swift` | No more in-memory vector index |
| `Services/Tools/SearchProjectTool.swift` | Replaced by SearchCodeTool |
| `Services/Tools/SearchProjectTool+v2.swift` | Replaced by SearchCodeTool+v2 |
| `Services/Tools/GrepTool.swift` | Replaced (search_code includes text search) |
| `Services/Tools/FindFileTool.swift` | Replaced (search_code includes file search) |
| `Services/Tools/FindFileTool+v2.swift` | Replaced |
| `Services/Tools/LocalFindTool.swift` | Replaced |
| `Services/Tools/IndexSearchTextTool.swift` | Replaced |
| `Services/Tools/IndexSearchSymbolsTool.swift` | Replaced |
| `Services/Tools/IndexFindFilesTool.swift` | Replaced |
| `Services/Tools/IndexListFilesTool.swift` | Replaced |
| `Services/Tools/IndexReadFileTool.swift` | Replaced (keep read_file tool instead) |
| `Services/Tools/GetProjectStructureTool.swift` | Keep as separate non-search tool |
