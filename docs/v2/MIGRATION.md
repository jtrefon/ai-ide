# Migration Plan — v2 Search + RAG Decomposition

> **Strategy:** Incremental. Each phase is independent and backwards-compatible. Work through them in order. Test after each phase.

## Phase 0: Preparation (No Behavior Change)

**Goal:** Create the new directory structure and database schema without changing any behavior.

### Step 0.1 — Create Directories

```
mkdir -p osx-ide/Services/Search
mkdir -p osx-ide/Services/Memory
```

### Step 0.2 — Create `project_memory.sqlite` Schema

Create `Services/Memory/MemoryStore.swift` — a new `DatabaseStore`-like class for the separate memory database.

```swift
// MemoryStore.swift — NEW FILE
// Database wrapper for project_memory.sqlite
// Contains: project_info, memories, memory_embeddings, search_cache, chat_summaries tables
```

**Schema:** See [PROJECT_MEMORY.md](PROJECT_MEMORY.md#2-database-schema)

**Test:** MemoryStore creates the database file on init. Querying an empty database returns empty results.

### Step 0.3 — Add `signature` and `parent_symbol_id` Columns to `codebase.sqlite`

Add these columns to the `symbols` table. They're optional (nullable) and existing data works without them.

```sql
ALTER TABLE symbols ADD COLUMN signature TEXT;
ALTER TABLE symbols ADD COLUMN parent_symbol_id TEXT;
CREATE INDEX IF NOT EXISTS idx_symbols_kind ON symbols(kind);
```

**Test:** Existing search still works. New columns are empty/NULL.

---

## Phase 1: Strip Vectors from Search Index

**Goal:** Remove vector storage, code chunks, and HNSW from the search index. No new tools yet — just cleanup.

### Step 1.1 — Remove `updateCodeChunks` from IndexerActor

**File:** `Services/Index/Indexing/IndexerActor.swift`

**Change:** In `upsertResourceAndIndexSymbols()`, remove the `try await updateCodeChunks(...)` call (line 172).

```swift
// BEFORE:
try await storeSymbolsIfNeeded(symbols, resourceId: request.resourceId, fileName: request.url.lastPathComponent)
try await updateCodeChunks(content: request.content, resourceId: request.resourceId)

// AFTER:
try await storeSymbolsIfNeeded(symbols, resourceId: request.resourceId, fileName: request.url.lastPathComponent)
// updateCodeChunks removed — no more embedding generation for code
```

**Test:** Run a full re-index. It should complete in seconds, not minutes. Existing search still works (FTS5 + symbols unchanged).

### Step 1.2 — Remove `HNSWIndex.swift`

**File:** `Services/Index/Search/HNSWIndex.swift`

**Action:** Delete the entire file.

**Compensation:** Update `DatabaseCodeChunkManager` references that use `hnswIndices`. Actually...

### Step 1.3 — Remove `DatabaseCodeChunkManager.swift`

**File:** `Services/Index/Database/DatabaseCodeChunkManager.swift`

**Action:** Delete the entire file.

### Step 1.4 — Remove Vector Methods from `DatabaseStore.swift`

**File:** `Services/Index/Database/DatabaseStore.swift`

**Change:** Remove these methods:
- `replaceCodeChunks(resourceId:modelId:chunks:)`
- `deleteCodeChunks(resourceId:modelId:)`
- `searchSimilarCodeChunks(modelId:queryVector:limit:)`

**Test:** Build the project. No references to code_chunks, HNSWIndex, or vector operations remain.

### Step 1.5 — Remove Vector Tables from Schema

**File:** `Services/Index/Database/DatabaseSchemaManager.swift`

**Change:** Remove these table definitions from `createBaseSchema()`:
- `code_chunks` table (lines 68-80)
- `memory_embeddings` table (lines 58-66) — only if memories are moving entirely to project_memory.sqlite

**Test:** Create a fresh index. The `code_chunks` and `memory_embeddings` tables don't exist.

### Step 1.6 — Remove Embedding Extensions from CodebaseIndex

**File:** `Services/Index/CodebaseIndex+SymbolsAndMemories.swift`

**Change:** Remove:
- Extension `CodebaseIndex: MemoryEmbeddingSearchProviding` (lines 40-88)
- Extension `CodebaseIndex: CodeChunkEmbeddingSearchProviding` (lines 90-119)
- Method `getSummaries(projectRoot:limit:)` — only if moving to new system
- Method `getMemories(tier:)` — only if moving to new system

**Test:** Build the project. No references to `getRelevantCodeChunks` or `getRelevantMemories`.

---

## Phase 2: Create `search_code` Tool

**Goal:** Implement and register the new single search tool.

### Step 2.1 — Create `SearchQueryEngine.swift`

**File:** `Services/Search/SearchQueryEngine.swift`

A non-actor class that executes SQL queries against `DatabaseStore`. Methods:

```swift
class SearchQueryEngine {
    let database: DatabaseStore  // codebase.sqlite

    func search(query: String, kind: String?, path: String?, maxResults: Int) async throws -> [SearchResult]
    func searchByText(query: String, path: String?, maxResults: Int) async throws -> [SearchResult]
    func listFiles(path: String?, limit: Int, offset: Int) async throws -> [String]
    func symbolsInFile(path: String) async throws -> [Symbol]
}
```

**Test:** Write unit tests that populate a test database with symbols, then query using SearchQueryEngine.

### Step 2.2 — Create `SearchCodeTool.swift`

**File:** `Services/Search/SearchCodeTool.swift`

Implements `AITool` protocol:

```swift
struct SearchCodeTool: AITool {
    let name = "search_code"
    let description = "Find code by name, kind, or content..."
    var parameters: [String: Any] { ... }

    let queryEngine: SearchQueryEngine

    func execute(arguments: ToolArguments) async throws -> String { ... }
}
```

**Test:** Register in ConversationToolProvider (replacing old search tools), run integration test with a real query.

### Step 2.3 — Create `SearchCodeTool+v2.swift`

**File:** `Services/Search/SearchCodeTool+v2.swift`

Implements `ToolDefinition` for the new architecture (if the new ToolRegistrar system is active).

```swift
struct SearchCodeToolV2: Sendable {
    let queryEngine: SearchQueryEngine
    func definition() -> ToolDefinition { ... }
}
```

### Step 2.4 — Update `ConversationToolProvider.swift`

**File:** `Services/ConversationToolProvider.swift`

**Changes:**

```swift
// Remove these lines:
tools.append(SearchProjectTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
tools.append(LocalFindTool(index: codebaseIndexProvider(), projectRoot: projectRoot))
tools.append(GrepTool(pathValidator: pathValidator))
tools.append(FindFileTool(pathValidator: pathValidator))
tools.append(IndexSearchTextTool(index: index))
tools.append(IndexSearchSymbolsTool(index: index))
tools.append(IndexFindFilesTool(index: index))
tools.append(IndexListFilesTool(index: index))
tools.append(IndexReadFileTool(index: index))
tools.append(IndexListMemoriesTool(index: index))
tools.append(IndexAddMemoryTool(index: index))

// Add:
let searchEngine = SearchQueryEngine(database: codebaseDatabase)
tools.append(SearchCodeTool(queryEngine: searchEngine))
```

**Also:** Remove the `index_list_memories` and `index_add_memory` tools from the placeholder list in `ToolRegistrar.swift` (lines 63-64). They'll be replaced by `project_context` and `remember`.

**Test:** The LLM sees `search_code` instead of the 11 old search tools. Verify with a debug print of available tools.

---

## Phase 3: Create `project_memory` System

**Goal:** Implement the memory database, retrieval, storage, and tools.

### Step 3.1 — Create `MemoryStore.swift`

**File:** `Services/Memory/MemoryStore.swift`

Actor-based SQLite wrapper for `project_memory.sqlite`. Methods:

```swift
actor MemoryStore {
    // Project info
    func getProjectInfo(key: String) throws -> String?
    func setProjectInfo(key: String, value: String) throws

    // Memories
    func storeMemory(content: String, category: String, source: String, importance: Double) throws -> String
    func searchMemories(query: String, limit: Int) throws -> [MemoryEntry]
    func deleteMemory(id: String) throws

    // Search cache
    func getCachedResult(queryHash: String) throws -> CachedSearchResult?
    func cacheResult(queryHash: String, query: String, summary: String, json: String) throws

    // Chat summaries
    func storeChatSummary(conversationId: String, summary: String, decisions: [String], files: [String], concepts: [String]) throws
    func searchChatSummaries(query: String, limit: Int) throws -> [ChatSummary]
}
```

### Step 3.2 — Create `MemoryRetriever.swift`

**File:** `Services/Memory/MemoryRetriever.swift`

Combines results from memories, project_info, and chat_summaries:

```swift
struct MemoryRetriever {
    let store: MemoryStore

    func retrieve(query: String, maxResults: Int) async throws -> MemoryRetrievalResult {
        // 1. FTS5 search on memories
        // 2. Keyword match on project_info keys
        // 3. FTS5 search on chat_summaries
        // 4. Optional: embedding vector search
        // 5. Merge, deduplicate, rank
        // 6. Return top N
    }
}
```

### Step 3.3 — Create `SearchCacheManager.swift`

**File:** `Services/Memory/SearchCacheManager.swift`

```swift
actor SearchCacheManager {
    let store: MemoryStore
    let defaultTTL: TimeInterval = 3600

    func lookup(query: String) async -> CachedSearchResult?
    func store(query: String, result: SearchResult) async
    func invalidateAll() async  // Called on project file change
}
```

### Step 3.4 — Create `ConversationSummarizer.swift`

**File:** `Services/Memory/ConversationSummarizer.swift`

```swift
actor ConversationSummarizer {
    let memoryStore: MemoryStore
    let llm: AIService  // or nil to skip LLM-based summarization

    func summarizeIfNeeded(conversationId: String, messages: [ChatMessage]) async throws {
        guard shouldSummarize(messages) else { return }

        if let llm {
            let summary = try await llm.generateStructuredSummary(of: messages)
            try await storeSummary(summary)
        } else {
            // Fallback: extract file paths and basic info from tool calls
            try await storeBasicSummary(messages)
        }
    }
}
```

### Step 3.5 — Create `ProjectMetadataGenerator.swift`

**File:** `Services/Memory/ProjectMetadataGenerator.swift`

One-time generation on project open:

```swift
actor ProjectMetadataGenerator {
    let memoryStore: MemoryStore

    func generateIfNeeded(projectRoot: URL) async throws {
        guard try await memoryStore.getProjectInfo(key: "language") == nil else { return }

        // Detect project type from file patterns
        // Store: language, framework, build_system, etc.
    }
}
```

### Step 3.6 — Create `ProjectContextTool.swift` and `RememberTool.swift`

**Files:**
- `Services/Memory/ProjectContextTool.swift`
- `Services/Memory/RememberTool.swift`
- `Services/Memory/ProjectContextTool+v2.swift` (if using new system)
- `Services/Memory/RememberTool+v2.swift` (if using new system)

Both implement `AITool` protocol with the contracts defined in [TOOL_CONTRACTS.md](TOOL_CONTRACTS.md).

### Step 3.7 — Wire into ConversationToolProvider

**File:** `Services/ConversationToolProvider.swift`

**Add:**

```swift
let memoryStore = MemoryStore(path: memoryDbPath)
tools.append(ProjectContextTool(memoryStore: memoryStore))
tools.append(RememberTool(memoryStore: memoryStore))
```

---

## Phase 4: Remove Old RAG Pipeline

**Goal:** Delete the old RAG infrastructure now that project_memory replaces it.

### Step 4.1 — Delete RAG Files

| File | Action |
|------|--------|
| `Services/RAG/CodebaseIndexRAGRetriever.swift` | Delete |
| `Services/RAG/RAGEvidenceFusionRanker.swift` | Delete |
| `Services/RAG/RetrievalIntentClassifier.swift` | Delete |

### Step 4.2 — Simplify `RAGContextBuilder.swift`

**File:** `Services/RAG/RAGContextBuilder.swift`

- Remove reference to `RAGEvidenceFusionRanker`
- Simplify to just format results from project_memory
- Keep the stage-based budget trimming (that's still useful)

### Step 4.3 — Remove Old Memory Files from Index

| File | Action |
|------|--------|
| `Services/Index/Memory/MemoryManager.swift` | Move to `Services/Memory/MemoryManager.swift` |
| `Services/Index/Memory/MemoryEmbeddingGenerator.swift` | Move to `Services/Memory/MemoryEmbeddingGenerator.swift` |
| `Services/Index/Database/DatabaseMemoryManager.swift` | Merge into `Services/Memory/MemoryStore.swift` |

### Step 4.4 — Update System Prompt

Remove instructions about the old search tools. Add guidance for the new tools:

```
OLD: "Use search_project for ALL code discovery. Use grep only when search_project fails."
NEW: "Use search_code for ALL code navigation. Use project_context for project knowledge. Use remember to store what you learn."
```

---

## Phase 5: Wire Conversation Summarizer

**Goal:** Auto-generate and store memory from conversations.

### Step 5.1 — Hook into ConversationManager

**File:** `Services/ConversationManager.swift`

After `sendCoordinator.send(...)` completes and the run is done, trigger summarization:

```swift
// At the end of startSendTask, after run completes:
if self.currentMode == .coder || self.currentMode == .agent {
    Task.detached(priority: .background) {
        try? await conversationSummarizer.summarizeIfNeeded(
            conversationId: self.conversationId,
            messages: self.historyCoordinator.messages
        )
    }
}
```

### Step 5.2 — Hook Search Cache

**File:** `Services/Search/SearchCodeTool.swift`

After returning results, cache them:

```swift
// After successful query
Task.detached(priority: .utility) {
    try? await searchCacheManager.store(query: arguments.query, result: results)
}
```

---

## Phase 6: Polish & Cleanup

**Goal:** Remove dead code, update tests, ensure everything works.

### Step 6.1 — Remove Dead Tool Files

Delete all files listed in [SEARCH_CODE.md §9](SEARCH_CODE.md#9-files-to-delete).

### Step 6.2 — Update Placeholder Tools in ToolRegistrar

**File:** `Services/Tooling/Registry/ToolRegistrar.swift`

Remove search-related placeholder tools from `placeholderTools` array (lines 57-66):

```swift
// Remove these entries:
("index_search_text", ...)
("index_search_symbols", ...)
("index_find_files", ...)
("index_list_files", ...)
("index_read_file", ...)
("index_list_memories", ...)
("index_add_memory", ...)
```

Replace with the new tool definitions.

### Step 6.3 — Update Tests

- `Services/Indexer/IndexToolsTests.swift` — update to use new tools
- `Services/RAG/RAGEvidenceFusionRankerTests.swift` — delete (ranker is gone)
- `SearchNavigationTests.swift` — update to use `search_code`
- Unit tests for `SearchQueryEngine`, `MemoryStore`, `MemoryRetriever`

### Step 6.4 — Performance Validation

Run benchmarks:

| Test | Expected |
|------|----------|
| Full re-index of osx-ide itself (~5K files) | < 5 seconds |
| `search_code("DatabaseManager")` | < 50 ms |
| `project_context("architecture")` | < 100 ms (FTS5) or < 500 ms (with vectors) |
| Cache hit `search_code` | < 5 ms |

---

## Rollback Plan

If something goes wrong:

1. **Phase 1** (strip vectors): Revert the IndexerActor change. All deleted files are in git history.
2. **Phase 2** (search_code tool): Keep old tools registered alongside new one. The LLM may use either. Remove old tools after verifying new one works.
3. **Phase 3** (memory system): project_memory.sqlite is a separate file. Deleting it doesn't affect codebase.sqlite. The old RAG pipeline can be re-enabled if needed.
4. **Phase 4** (delete old RAG): Files are in git. Revert and restore.

**Key safety measure:** Never modify existing database files in-place. `codebase.sqlite` schema changes (adding columns) are additive. The critical deletion is `code_chunks` table content, but that's purely derived data that gets regenerated on re-index.

---

## Implementation Order (Recommended)

```
Week 1: Phase 0 + Phase 1 (strip vectors, no new tools)
  → Verify: index time drops from minutes to seconds

Week 2: Phase 2 (search_code tool)
  → Verify: only 1 search tool instead of 14, all queries work

Week 3: Phase 3 (project_memory system)
  → Verify: can store and retrieve memories, search cache works

Week 4: Phase 4 + Phase 5 (delete old RAG, wire summarizer)
  → Verify: old RAG is gone, chat summaries auto-generate

Week 5: Phase 6 (cleanup, tests, polish)
  → Final validation and cleanup
```
