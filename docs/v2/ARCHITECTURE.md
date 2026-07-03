# v2 Search + RAG Decomposition — Architecture

## 1. High-Level Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        LLM Agent                                  │
│                                                                   │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────┐     │
│  │ search_code │  │ project_context  │  │ remember         │     │
│  │ (read-only) │  │ (read-only)      │  │ (write)          │     │
│  └──────┬──────┘  └───────┬──────────┘  └────────┬─────────┘     │
│         │                 │                       │               │
└─────────┼─────────────────┼───────────────────────┼───────────────┘
          │                 │                       │
          ▼                 ▼                       ▼
┌──────────────────┐  ┌───────────────────────────────────────┐
│  search_code     │  │  project_memory                        │
│  (SQLite DB)     │  │  (SQLite DB + optional sqlite-vec)     │
│                  │  │                                        │
│  ┌────────────┐  │  │  ┌─────────────────────────────────┐   │
│  │ resources  │  │  │  │ project_info (key-value store)  │   │
│  ├────────────┤  │  │  ├─────────────────────────────────┤   │
│  │ symbols    │  │  │  │ memories (agent knowledge)      │   │
│  ├────────────┤  │  │  ├─────────────────────────────────┤   │
│  │ FTS5       │  │  │  │ chat_summaries                 │   │
│  └────────────┘  │  │  ├─────────────────────────────────┤   │
│                  │  │  │ search_cache (TTL-based)        │   │
│  Single file:    │  │  └─────────────────────────────────┘   │
│  codebase.sqlite │  │                                        │
└──────────────────┘  │  Single file:                           │
                      │  project_memory.sqlite                  │
                      └────────────────────────────────────────┘
```

## 2. Two Completely Separate Databases

```
codebase.sqlite                     project_memory.sqlite
─────────────────                   ─────────────────────
  resources                           project_info
  resources_fts (FTS5)                memories
  symbols                             memory_embeddings (optional)
                                      search_cache
                                      chat_summaries
```

- **Different files.** Different `DatabaseStore` instances. No shared tables.
- **Different lifecycles.** `codebase.sqlite` is rebuilt from source files. `project_memory.sqlite` persists across re-indexes.
- **Different update patterns.** `codebase.sqlite` updates on file save. `project_memory.sqlite` updates when the agent learns something.

## 3. Component Responsibilities

### 3.1 Search System

| Component | Responsibility |
|-----------|---------------|
| `SearchIndexer` | Watches files, parses symbols, populates SQLite. Replaces `IndexerActor`'s vector path |
| `SearchQueryEngine` | Executes queries against symbols + FTS5. Replaces `QueryService`'s vector path |
| `DatabaseStore` (search) | SQLite wrapper for `codebase.sqlite`. Only `resources`, `resources_fts`, `symbols` remain |
| Language parsers | Same as today. Extract symbols from each language |
| `search_code` tool | Thin wrapper around `SearchQueryEngine` |

### 3.2 Memory System

| Component | Responsibility |
|-----------|---------------|
| `MemoryStore` | SQLite wrapper for `project_memory.sqlite`. CRUD for memories, summaries, cache |
| `MemoryRetriever` | Queries memories + cache + project_info. Uses FTS5 or optional vector search |
| `ConversationSummarizer` | After each conversation, generates a structured summary and stores it |
| `SearchCacheManager` | Caches `search_code` results with TTL. Re-uses cached results for identical queries |
| `ProjectMetadataGenerator` | One-time: generates project metadata (language, framework, architecture) on project open |
| `project_context` tool | Thin wrapper around `MemoryRetriever` |
| `remember` tool | Thin wrapper around `MemoryStore` write |

## 4. Data Flow

### 4.1 Indexing Flow (Search)

```
File saved / project opened
  → SearchIndexer.indexFile(url)
    → LanguageDetector.detect(at: url)
    → Parse symbols from content
    → Upsert resource + FTS in SQLite
    → Delete old symbols for this resource
    → Insert new symbols
  → Done in < 50ms per file
```

### 4.2 Query Flow (Search)

```
LLM calls search_code(query: "DataManager", kind: "class")
  → SearchQueryEngine.query("DataManager", kind: "class")
    → SELECT ... FROM symbols WHERE name LIKE '%DataManager%' AND kind = 'class'
    → Join with resources for path
    → Return [{file, line, kind, name, signature}]
  → Also check search_cache in project_memory
    → If found, cache hit — return cached + fresh results merged
    → If not found, cache the result
  → Format and return to LLM
```

### 4.3 Memory Flow

```
LLM calls project_context(query: "How do we handle auth?")
  → MemoryRetriever.retrieve("How do we handle auth?")
    → Query FTS5 over memories + project_info + chat_summaries
    → Optionally: generate embedding and query memory_embeddings
    → Rank by relevance (simple: FTS score + recency)
    → Return top 5 results
  → Format as context block for LLM
```

### 4.4 Chat Summary Flow

```
Conversation ends (LLM produces final response)
  → System triggers ConversationSummarizer
    → LLM generates structured summary of the conversation
      { summary, files_touched, key_decisions, concepts_discovered }
    → MemoryStore.storeChatSummary(summary)
    → For each key_decision:
        MemoryStore.storeMemory(content, category: "decision")
    → For each concept_discovered:
        MemoryStore.storeMemory(content, category: "note")
```

## 5. Tool Registration

Both old and new tool architectures should register these tools:

### Old AITool system (ConversationToolProvider)

```swift
// Remove from allTools():
//   SearchProjectTool, LocalFindTool, GrepTool, FindFileTool
//   IndexSearchTextTool, IndexSearchSymbolsTool, IndexFindFilesTool
//   IndexListFilesTool, IndexReadFileTool, IndexListMemoriesTool, IndexAddMemoryTool
//   GetProjectStructureTool (keep as separate non-search tool)

// Add:
tools.append(SearchCodeTool(database: searchDatabase))
tools.append(ProjectContextTool(memoryStore: memoryStore))
tools.append(RememberTool(memoryStore: memoryStore))
```

### New ToolRegistrar system

```swift
// Register search_code as a full implementation (not placeholder)
r.register(SearchCodeToolV2(database: searchDatabase).definition())

// Register project_context and remember as implementations
r.register(ProjectContextToolV2(memoryStore: memoryStore).definition())
r.register(RememberToolV2(memoryStore: memoryStore).definition())
```

## 6. File Locations

```
osx-ide/Services/
├── Search/                              ← NEW: Search system
│   ├── SearchIndexer.swift               ← File watcher + indexer
│   ├── SearchQueryEngine.swift           ← Query execution
│   ├── SearchCodeTool.swift              ← search_code tool (AITool protocol)
│   └── SearchCodeTool+v2.swift           ← search_code tool (ToolDefinition)
│
├── Memory/                              ← NEW: Memory system
│   ├── MemoryStore.swift                 ← SQLite wrapper for project_memory.sqlite
│   ├── MemoryRetriever.swift             ← Query + ranking
│   ├── ConversationSummarizer.swift      ← Post-chat summary generation
│   ├── SearchCacheManager.swift          ← TTL-based cache
│   ├── ProjectMetadataGenerator.swift    ← One-time project metadata
│   ├── ProjectContextTool.swift          ← project_context tool (AITool)
│   ├── ProjectContextTool+v2.swift       ← project_context tool (ToolDefinition)
│   ├── RememberTool.swift               ← remember tool (AITool)
│   └── RememberTool+v2.swift            ← remember tool (ToolDefinition)
│
├── Index/                               ← Keep but simplify
│   ├── CodebaseIndex.swift              ← Strip: remove code_chunks, vector paths
│   ├── CodebaseIndex+TextSearch.swift   ← Keep as-is
│   ├── CodebaseIndex+SymbolsAndMemories.swift ← Strip: remove getRelevantCodeChunks, getRelevantMemories
│   ├── CodebaseIndexProtocol.swift      ← Keep but can simplify protocol
│   ├── Database/
│   │   ├── DatabaseSchemaManager.swift  ← Remove code_chunks, memory_embeddings tables
│   │   ├── DatabaseCodeChunkManager.swift ← DELETE entire file
│   │   ├── DatabaseMemoryManager.swift  ← MOVE to Memory/MemoryStore.swift
│   │   └── DatabaseStore.swift          ← Remove code_chunks methods
│   ├── Search/
│   │   └── HNSWIndex.swift              ← DELETE entire file
│   ├── Indexing/
│   │   └── IndexerActor.swift           ← Remove updateCodeChunks call
│   ├── Memory/
│   │   ├── MemoryEmbeddingGenerator.swift ← KEEP for optional memory vectors
│   │   ├── MemoryManager.swift          ← MOVE to Memory/
│   │   └── ...                          ← Keep what's needed for memory
│   └── ...
│
└── RAG/                                 ← DELETE or drastically simplify
    ├── CodebaseIndexRAGRetriever.swift   ← DELETE (replaced by MemoryRetriever)
    ├── RAGEvidenceFusionRanker.swift     ← DELETE
    ├── RAGContextBuilder.swift           ← KEEP but simplify (remove fusion, keep formatting)
    ├── RAGModels.swift                  ← KEEP (models still useful)
    └── RetrievalIntentClassifier.swift  ← DELETE (over-engineered for current needs)
```

## 7. Simplification of Existing Files

| Current File | Action |
|-------------|--------|
| `DatabaseCodeChunkManager.swift` | **Delete.** The code_chunks concept is gone. |
| `HNSWIndex.swift` | **Delete.** Replaced by nothing (FTS5 is sufficient). |
| `CodebaseIndexRAGRetriever.swift` | **Delete.** Replaced by `MemoryRetriever`. |
| `RAGEvidenceFusionRanker.swift` | **Delete.** No more hand-tuned ranking. |
| `RetrievalIntentClassifier.swift` | **Delete.** Over-engineered for current needs. |
| `DatabaseSchemaManager.swift` | **Edit.** Remove `code_chunks` and `memory_embeddings` table creation. |
| `CodebaseIndex+SymbolsAndMemories.swift` | **Edit.** Remove `getRelevantCodeChunks` and `getRelevantMemories` extensions. |
| `IndexerActor.swift` | **Edit.** Remove `updateCodeChunks` call. Keep symbol extraction + FTS. |
| `DatabaseStore.swift` | **Edit.** Remove `replaceCodeChunks`, `deleteCodeChunks`, `searchSimilarCodeChunks`. |
| `RAGContextBuilder.swift` | **Keep but simplify.** Remove fusion ranker reference. Keep formatting logic. |
| `RAGModels.swift` | **Keep.** Data models are still useful. |
| `MemoryEmbeddingGenerator.swift` | **Keep.** Useful if memory system wants optional vector search. |
