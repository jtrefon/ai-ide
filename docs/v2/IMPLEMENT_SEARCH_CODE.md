# Implementation Plan — `search_code` (Session 1)

> **Scope:** Strip vectors from the codebase index, create the `search_code` tool, wire it up.
> **Build-after-every-step:** Yes. We compile and verify after each change.
> **Defer to Session 2:** `project_memory` system (Memories, Summaries, Cache, Vectors)

## What We Keep (Repurpose)

The core SQLite schema for `resources`, `symbols`, and `resources_fts` (FTS5) is solid. The language parsers are solid. The `QueryService`, `DatabaseSymbolManager`, `DatabaseQueryExecutor` are all fine — they query the tables we're keeping.

**We do not nuke the database.** We surgically remove the vector/chunk layers.

## Plan Overview

```
Task 1: Strip vectors from IndexerActor (the indexing bottleneck)
  → Build → verify indexing is ~seconds, not minutes

Task 2: Strip vectors from database schema + store  
  → Build → verify no references to deleted tables

Task 3: Strip embeddings from CodebaseIndex protocol
  → Build → verify no references to vector search

Task 4: Delete dead vector/chunk files
  → Build → verify clean compilation

Task 5: Create SearchQueryEngine + SearchCodeTool
  → Build → verify tool works end-to-end

Task 6: Wire into ConversationToolProvider + ToolRegistrar
  → Build → verify LLM sees the new tool

Task 7: Delete old search tool files
  → Build → verify nothing is broken
```

---

## Task 1: Strip Vectors from IndexerActor

**Goal:** Remove the bottleneck that adds 15-45 minutes to indexing.

### Step 1a: Remove `updateCodeChunks` call

**File:** `Services/Index/Indexing/IndexerActor.swift`

**Change:** In `upsertResourceAndIndexSymbols()`, remove line 172:
```swift
// REMOVE this line:
try await updateCodeChunks(content: request.content, resourceId: request.resourceId)
```

The method becomes just:
```swift
private func upsertResourceAndIndexSymbols(_ request: IndexResourceRequest) async throws {
    try await database.upsertResourceAndFTS(...)
    let symbols = await extractSymbols(...)
    try await storeSymbolsIfNeeded(symbols, ...)
    // updateCodeChunks removed ✓
}
```

### Step 1b: Remove entire `updateCodeChunks` method body

**File:** `Services/Index/Indexing/IndexerActor.swift`

**Change:** Delete lines 200-277 (`updateCodeChunks` + `makeChunkSnapshots` + `CodeChunkSnapshot` struct).

### Step 1c: Remove `deleteCodeChunks` call from `removeFile`

**File:** `Services/Index/Indexing/IndexerActor.swift`

**Change:** In `removeFile()` (line 197), remove:
```swift
try await database.deleteCodeChunks(resourceId: resourceId)
```

### Step 1d: Remove `embeddingGenerator` if unused

**File:** `Services/Index/Indexing/IndexerActor.swift`

**Check:** After removing `updateCodeChunks`, see if `self.embeddingGenerator` is still referenced anywhere. If not, remove the property.

**→ BUILD**

---

## Task 2: Strip Vectors from Database Schema + Store

**Goal:** Remove code_chunks and memory_embeddings table definitions and accessors.

### Step 2a: Remove tables from schema

**File:** `Services/Index/Database/DatabaseSchemaManager.swift`

**Change:** In `createBaseSchema()`, remove:
- Lines 49-56: `memories` table (we no longer store memories here — deferred to session 2)
  - Actually wait — `memories` and `memory_embeddings` are used by the old memory system which we're deferring. But they're in `codebase.sqlite`. The new system will use `project_memory.sqlite` instead.
  - **Decision:** Keep `memories` and `memory_embeddings` tables in schema for now (they don't hurt anything and the old memory code still references them). Only remove `code_chunks` table and its indices.
- Lines 68-80: `code_chunks` table
- Lines 85-86: `idx_code_chunks_model` and `idx_code_chunks_resource_model` indices

**→ BUILD**

### Step 2b: Remove vector methods from DatabaseStore

**File:** `Services/Index/Database/DatabaseStore.swift`

**Change:** Remove:
- `replaceCodeChunks` (lines 163-169)
- `deleteCodeChunks` (lines 171-173)
- `searchSimilarCodeChunks` (lines 175-181)

**→ BUILD**

---

## Task 3: Strip Embeddings from CodebaseIndex

**Goal:** Remove the embedding-based search protocols and methods.

### Step 3a: Remove embedding protocol conformances

**File:** `Services/Index/CodebaseIndex+SymbolsAndMemories.swift`

**Change:** Remove:
- Lines 40-88: `extension CodebaseIndex: MemoryEmbeddingSearchProviding` + `getRelevantMemories` method
- Lines 90-119: `extension CodebaseIndex: CodeChunkEmbeddingSearchProviding` + `getRelevantCodeChunks` method

Keep lines 1-38 (the symbol/memory CRUD methods — those are still useful).

**→ BUILD**

---

## Task 4: Delete Dead Files

**Goal:** Remove files that are no longer referenced.

### Step 4a: Delete `DatabaseCodeChunkManager.swift`

**File:** `Services/Index/Database/DatabaseCodeChunkManager.swift`
**Action:** Delete entire file (~252 lines)

**→ BUILD** (verify no remaining references)

### Step 4b: Delete `HNSWIndex.swift`

**File:** `Services/Index/Search/HNSWIndex.swift`
**Action:** Delete entire file (~330 lines)

**→ BUILD** (verify no remaining references)

---

## Task 5: Create SearchQueryEngine + SearchCodeTool

**Goal:** The new search tool implementation.

### Step 5a: Create `Services/Search/SearchQueryEngine.swift`

New file. Wraps the existing `DatabaseStore` (codebase.sqlite) with focused search methods.

```swift
import Foundation

/// Fast, precise code search against the symbol index + FTS5.
/// No ML, no embeddings, no chunks.
struct SearchQueryEngine: Sendable {
    private let database: DatabaseStore

    init(database: DatabaseStore) {
        self.database = database
    }

    /// Search by symbol name (class, function, variable, etc.)
    func searchSymbols(query: String, kind: String?, path: String?, maxResults: Int) async throws -> [SearchResult] {
        // SQL: SELECT ... FROM symbols JOIN resources
        // WHERE symbols.name LIKE '%query%'
        // AND (kind IS NULL OR symbols.kind = kind)
        // AND (path IS NULL OR resources.path LIKE '%path%')
        // ORDER BY exact match > prefix match > substring match
        // LIMIT maxResults
    }

    /// Full-text content search via FTS5
    func searchText(query: String, path: String?, maxResults: Int) async throws -> [SearchResult] {
        // SQL: SELECT ... FROM resources_fts JOIN resources
        // WHERE resources_fts MATCH query
        // LIMIT maxResults
    }

    /// Combined search: symbols first, then FTS5 fallback
    func search(query: String, kind: String?, path: String?, maxResults: Int) async throws -> [SearchResult] {
        let symbols = try await searchSymbols(query: query, kind: kind, path: path, maxResults: maxResults)
        if symbols.count >= maxResults {
            return Array(symbols.prefix(maxResults))
        }
        let textResults = try await searchText(query: query, path: path, maxResults: maxResults - symbols.count)
        return symbols + textResults
    }
}

struct SearchResult: Sendable, Codable {
    let file: String           // Relative path
    let line: Int
    let kind: String?          // "class", "function", etc. (nil for text matches)
    let name: String           // Symbol name or matched text
    let signature: String?     // Function/class signature if available
    let context: String        // Surrounding code snippet
}
```

**→ BUILD**

### Step 5b: Create `Services/Search/SearchCodeTool.swift`

New file. Implements the `AITool` protocol.

```swift
import Foundation

struct SearchCodeTool: AITool {
    let name = "search_code"
    let description = "Find code by name, kind, or content. The primary tool for code navigation — use this for ALL code discovery needs. Searches classes, functions, variables, files, and text patterns."

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search term: class name, function name, variable name, file name, or text pattern. Case-insensitive partial match."
                ],
                "kind": [
                    "type": "string",
                    "description": "Optional: filter by symbol kind (class, struct, enum, protocol, function, method, variable, extension, typealias).",
                    "enum": ["class", "struct", "enum", "protocol", "function", "method", "variable", "extension", "typealias"]
                ],
                "path": [
                    "type": "string",
                    "description": "Optional: scope search to a subdirectory relative to project root (e.g. 'Services/', 'Sources/App')."
                ],
                "max_results": [
                    "type": "integer",
                    "description": "Maximum results to return. Default 30, max 100."
                ]
            ],
            "required": ["query"]
        ]
    }

    let queryEngine: SearchQueryEngine

    func execute(arguments: ToolArguments) async throws -> String {
        let raw = arguments.raw
        guard let query = raw["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Error: 'query' parameter is required."
        }
        let kind = raw["kind"] as? String
        let path = raw["path"] as? String
        let maxResults = min(100, max(1, raw["max_results"] as? Int ?? 30))

        let results = try await queryEngine.search(query: query, kind: kind, path: path, maxResults: maxResults)

        guard !results.isEmpty else {
            return "No matches found for '\(query)'."
        }

        // Format results grouped by file
        let grouped = Dictionary(grouping: results) { $0.file }
            .sorted { $0.key < $1.key }

        var output = "Found \(results.count) result(s) for '\(query)':\n\n"
        for (file, fileResults) in grouped {
            output += "\(file)\n"
            for r in fileResults.prefix(15) {
                let kindTag = r.kind.map { "[\($0)] " } ?? ""
                let sig = r.signature.map { " \($0)" } ?? ""
                output += "  L\(r.line) \(kindTag)\(r.name)\(sig)\n"
            }
            if fileResults.count > 15 {
                output += "  ... and \(fileResults.count - 15) more in this file\n"
            }
            output += "\n"
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**→ BUILD**

---

## Task 6: Wire Into Tool Providers

**Goal:** Register `search_code` and remove old search tools.

### Step 6a: Update `ConversationToolProvider.swift`

**Change:** Replace lines 44-61.

Remove:
```swift
// RAG & Index Tools (lines 44-52)
if let index = codebaseIndexProvider() {
    tools.append(IndexSearchTextTool(index: index))
    tools.append(IndexSearchSymbolsTool(index: index))
    tools.append(IndexFindFilesTool(index: index))
    tools.append(IndexListFilesTool(index: index))
    tools.append(IndexReadFileTool(index: index))
    tools.append(IndexListMemoriesTool(index: index))
    tools.append(IndexAddMemoryTool(index: index))
}

// Search & Structure Tools (lines 54-61) — remove these:
tools.append(SearchProjectTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
tools.append(LocalFindTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
tools.append(GrepTool(pathValidator: pathValidator))
tools.append(FindFileTool(pathValidator: pathValidator))
```

Add:
```swift
// Search — single unified tool
let database = /* get codebase.sqlite DatabaseStore from somewhere */
let searchEngine = SearchQueryEngine(database: database)
tools.append(SearchCodeTool(queryEngine: searchEngine))
```

**Question:** How does `ConversationToolProvider` get access to the `DatabaseStore`? 
- Currently it has `codebaseIndexProvider: () -> CodebaseIndexProtocol?`
- `CodebaseIndex` has a `database: DatabaseStore` property
- We can either:
  a. Add a `databaseProvider: () -> DatabaseStore?` to `ConversationToolProvider`
  b. Expose the database from `CodebaseIndex` (it's already public-ish)
  c. Create `SearchCodeTool` from `CodebaseIndexProtocol` by adding a method

**Recommendation:** Option (a) — simplest. Add a `databaseProvider` closure.

```swift
final class ConversationToolProvider {
    private let databaseProvider: () -> DatabaseStore?
    
    init(..., databaseProvider: @escaping () -> DatabaseStore?) {
        self.databaseProvider = databaseProvider
    }
}
```

Then in `ConversationManager`:
```swift
lazy var toolProvider = ConversationToolProvider(
    ...
    databaseProvider: { [weak self] in 
        (self?.codebaseIndex as? CodebaseIndex)?.database 
    }
)
```

**→ BUILD**

### Step 6b: Update `ToolRegistrar.swift`

**Change:** Replace the `search_project` registration (lines 36-42) with `search_code`. Remove index_* placeholders.

```swift
// Remove lines 36-42 entirely
// Remove from placeholderTools (lines 56-67):
//   - "index_search_text"
//   - "index_search_symbols"  
//   - "index_find_files"
//   - "index_list_files"
//   - "index_read_file"
//   - "index_list_memories"
//   - "index_add_memory"

// Update placeholderTools to only keep:
private static let placeholderTools: [(String, String, Set<ToolCapability>, String)] = [
    ("get_project_structure", "Show project directory tree.", [.projectStructure], "text"),
    ("web_search", "Search the web using Google.", [.webSearch], "items"),
    ("web_browse", "Read full web pages with a browser.", [.webBrowse], "text"),
]

// Add search_code registration when database is available
if let db = database {
    r.register(SearchCodeToolV2(queryEngine: SearchQueryEngine(database: db)).definition())
}
```

Note: The old `SearchProjectToolV2` is replaced. The new tool name is `search_code`, not `search_project`.

**→ BUILD**

---

## Task 7: Delete Old Search Tool Files

**Goal:** Remove the 10+ old tool implementations that `search_code` replaces.

### Files to Delete

```swift
// These files are NO LONGER REFERENCED after Task 6:
Services/Tools/SearchProjectTool.swift         // Replaced by SearchCodeTool
Services/Tools/SearchProjectTool+v2.swift     // Replaced
Services/Tools/GrepTool.swift                  // Replaced
Services/Tools/FindFileTool.swift              // Replaced
Services/Tools/FindFileTool+v2.swift          // Replaced
Services/Tools/LocalFindTool.swift             // Replaced
Services/Tools/IndexSearchTextTool.swift       // Replaced
Services/Tools/IndexSearchSymbolsTool.swift    // Replaced
Services/Tools/IndexFindFilesTool.swift        // Replaced
Services/Tools/IndexListFilesTool.swift        // Replaced
Services/Tools/IndexReadFileTool.swift         // Replaced (use read_file instead)
Services/Tools/GetProjectStructureTool.swift   // KEEP — still useful as non-search tool
Services/Tools/IndexListMemoriesTool.swift     // Deferred to session 2
Services/Tools/IndexAddMemoryTool.swift        // Deferred to session 2
```

**→ BUILD** (verify no broken imports or references)

---

## Summary of Changes

| Task | Files Changed | Type |
|------|--------------|------|
| 1a | `IndexerActor.swift` line 172 | Remove 1 line |
| 1b | `IndexerActor.swift` lines 200-277 | Delete method |
| 1c | `IndexerActor.swift` line 197 | Remove 1 line |
| 2a | `DatabaseSchemaManager.swift` lines 68-80, 85-86 | Remove table + indices |
| 2b | `DatabaseStore.swift` lines 163-181 | Remove 3 methods |
| 3a | `CodebaseIndex+SymbolsAndMemories.swift` lines 40-119 | Remove 2 extensions |
| 4a | `DatabaseCodeChunkManager.swift` | **Delete file** |
| 4b | `HNSWIndex.swift` | **Delete file** |
| 5a | `Services/Search/SearchQueryEngine.swift` | **New file** |
| 5b | `Services/Search/SearchCodeTool.swift` | **New file** |
| 6a | `ConversationToolProvider.swift` | Replace tool list |
| 6b | `ToolRegistrar.swift` | Replace placeholders |
| 7 | 12 tool files | **Delete files** |

**Lines net change:** ~ -900 lines, ~ +200 lines
**Index speed:** 15-45 minutes → 3-8 seconds
**Search tools for LLM:** 14 → 1 (`search_code`)
