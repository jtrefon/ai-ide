# `project_memory` — Agent Knowledge & Context

## 1. Purpose

Provide the LLM agent with persistent project knowledge so it doesn't re-scan the codebase every turn. Stores what the agent learns: architecture, decisions, bug fixes, skills, and conversation summaries.

## 2. Database Schema

File: `{projectRoot}/.osx-ide/project_memory.sqlite`

```sql
-- Project metadata: key-value store for fast lookup
CREATE TABLE project_info (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at REAL NOT NULL
);

-- Agent memories: knowledge accumulated over time
CREATE TABLE memories (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,   -- "architecture" | "decision" | "bugfix" | "skill" | "note"
    content TEXT NOT NULL,
    source TEXT NOT NULL,     -- "manual" | "chat_summary" | "discovery" | "auto"
    importance REAL DEFAULT 0.5,  -- 0.0 to 1.0
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

-- Optional: vector embeddings for memories (only if using semantic search)
CREATE TABLE memory_embeddings (
    memory_id TEXT PRIMARY KEY,
    vector_blob BLOB NOT NULL,
    model_id TEXT NOT NULL,
    dimensions INTEGER NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
);

-- Search cache: avoid re-running expensive or identical searches
CREATE TABLE search_cache (
    query_hash TEXT PRIMARY KEY,
    query TEXT NOT NULL,
    result_summary TEXT NOT NULL,
    result_json TEXT,          -- Full structured result for reconstruction
    created_at REAL NOT NULL,
    ttl_seconds INTEGER DEFAULT 3600  -- 1 hour default TTL
);

-- Conversation summaries: what happened, what was learned
CREATE TABLE chat_summaries (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    summary TEXT NOT NULL,
    key_decisions TEXT,        -- JSON array of strings
    files_touched TEXT,        -- JSON array of strings
    concepts_discovered TEXT,  -- JSON array of strings
    created_at REAL NOT NULL
);

-- FTS for keyword search over memories + summaries
CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
    content,
    category UNINDEXED,
    memory_id UNINDEXED
);
```

## 3. Data Tables

### 3.1 `project_info` — Pre-populated on Project Open

This is generated once when a project is first opened, then updated manually or when the project structure changes significantly.

| Key | Example Value |
|-----|---------------|
| `language` | "Swift" |
| `framework` | "SwiftUI" |
| `architecture` | "MVVM with service layer" |
| `build_system` | "Xcode + SwiftPM" |
| `test_framework` | "XCTest" |
| `package_manager` | "SwiftPM" |
| `min_deployment_target` | "macOS 14.0" |
| `key_conventions` | "Uses snake_case for JSON, camelCase for Swift. All networking goes through NetworkService." |
| `project_description` | "An AI-powered IDE for macOS with code completion, chat, and agent features." |

### 3.2 `memories` — Accumulated Agent Knowledge

| category | What It Stores | Example |
|----------|---------------|---------|
| `architecture` | Project structure, patterns, conventions | "The app uses a Coordinator pattern for navigation. Each tab has its own coordinator." |
| `decision` | Why something was built a certain way | "We chose SQLite over CoreData because we need cross-platform compatibility." |
| `bugfix` | Bugs encountered and how they were fixed | "Ghost commit bug: SQLite WAL mode was not enabled. Fixed by adding PRAGMA journal_mode=WAL." |
| `skill` | How to do something in this project | "To add a new setting: 1) Add enum case to AppConstantsSettings, 2) Add toggle in AISettingsTab." |
| `note` | General useful information | "The project has 5 main targets: osx-ide, osx-ideTests, osx-ideUITests, osx-ideHarnessTests, Vendor." |

### 3.3 `search_cache` — Query Result Cache

- **Key:** SHA256 hash of the normalized query string
- **TTL:** 1 hour default (configurable)
- **Cache hit:** Re-use cached result instead of querying the search index
- **Cache miss:** Run query, store result, return
- **When cache is busted:** After any file change in the project (or when TTL expires)

```sql
-- Insert or update cache entry
INSERT INTO search_cache (query_hash, query, result_summary, result_json, created_at, ttl_seconds)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(query_hash) DO UPDATE SET
    result_summary = excluded.result_summary,
    result_json = excluded.result_json,
    created_at = excluded.created_at;

-- Query with TTL check
SELECT * FROM search_cache
WHERE query_hash = ?
  AND created_at + ttl_seconds > ?;
```

### 3.4 `chat_summaries` — Conversation History

Generated **after** each conversation completes. Never written by the LLM during a conversation.

```json
// Example entry
{
  "id": "cs_abc123",
  "conversation_id": "conv_456",
  "summary": "User asked about the ghost commit bug in DatabaseManager. Found that WAL mode was not enabled. Fixed by adding PRAGMA journal_mode=WAL to DatabaseManager.init.",
  "key_decisions": [
    "Enable SQLite WAL mode to prevent ghost commits"
  ],
  "files_touched": [
    "Services/Index/Database/DatabaseManager.swift"
  ],
  "concepts_discovered": [
    "ghost commit",
    "SQLite WAL mode",
    "journal_mode pragma"
  ]
}
```

## 4. Conversation Summarizer

**Triggered:** After each conversation (when the ToolLoop exits without pending tools)

**Implementation:**

```swift
actor ConversationSummarizer {
    private let memoryStore: MemoryStore
    private let llm: AIService  // Same LLM as the conversation, or a cheap one

    func summarize(conversationId: String, messages: [ChatMessage]) async throws {
        // 1. Check: was this conversation productive? (had tool calls, file writes, etc.)
        guard shouldSummarize(messages) else { return }

        // 2. Ask LLM to generate structured summary
        let summary = try await llm.generateSummary(
            of: messages,
            format: .structured  // { summary, key_decisions, files_touched, concepts_discovered }
        )

        // 3. Store chat summary
        try await memoryStore.storeChatSummary(summary)

        // 4. Store key decisions as memories
        for decision in summary.key_decisions {
            try await memoryStore.storeMemory(
                content: decision,
                category: "decision",
                source: "chat_summary"
            )
        }

        // 5. Store concepts as notes
        for concept in summary.concepts_discovered {
            try await memoryStore.storeMemory(
                content: concept,
                category: "note",
                source: "chat_summary"
            )
        }
    }

    private func shouldSummarize(_ messages: [ChatMessage]) -> Bool {
        // Only summarize conversations that had tool activity
        messages.contains { $0.isToolExecution || $0.hasToolCalls }
    }
}
```

## 5. Construction Summarizer (Alternative to Conversation Summarizer)

Rather than summarizing entire chat sessions, an alternative approach is to **construct memories from artifacts produced during the conversation**. This is more targeted:

```
After a successful mutation (file write/edit):
  → Extract what changed from the tool call arguments
  → Store as a "note" memory with the file path and what was done

After a search_code call:
  → Cache the result in search_cache

After a bug fix pattern is detected:
  → Store as a "bugfix" memory
```

This approach doesn't require an LLM call and captures the signal directly from tool execution artifacts. The conversation summarizer is more comprehensive but requires an additional LLM call.

**Recommendation:** Start with artifact-based memory construction. Add conversation summarization later if needed.

## 6. Retrieval Pipeline

```
project_context(query: "How do we handle auth?")
  → MemoryRetriever.retrieve("How do we handle auth?", limit: 5)
    → Step 1: FTS5 search on memory_fts (keyword match on memories)
    → Step 2: Full-text search on chat_summaries.summary
    → Step 3: Key-value lookup on project_info (exact key match)
    → Step 4 (optional): Generate embedding → vector search on memory_embeddings
    → Merge results, deduplicate, rank by:
        priority = (exact_keyword_match ? 10 : FTS_score * 5) + recency_bonus + importance_bonus
    → Return top N results
```

## 7. Tool Definitions

See [TOOL_CONTRACTS.md](TOOL_CONTRACTS.md) for exact schemas.

### `project_context`

- **Purpose:** Retrieve relevant context about the project
- **When to use:** The LLM needs to understand project architecture, recall past decisions, or find learned patterns
- **Parameters:** `query: string`, `max_results?: int` (default 5, max 20)
- **Returns:** Formatted context block with memories, project info, and summaries

### `remember`

- **Purpose:** Explicitly store a memory
- **When to use:** The LLM discovers something worth remembering (architecture pattern, convention, decision)
- **Parameters:** `content: string`, `category: string` (architecture|decision|bugfix|skill|note), `importance?: float` (0.0-1.0, default 0.5)
- **Returns:** Confirmation message

## 8. Interaction with Search

```
LLM receives: "Where is DataManager class?"

Option A (no cache):
  → search_code(query: "DataManager", kind: "class")
  → Result: DataManager.swift line 42
  → SearchCacheManager caches the result for 1 hour

Option B (cache hit — same query within TTL):
  → project_context(query: "DataManager") — implicit cache check
  → OR search_code runs and hits the cache internally
  → Result returned instantly from cache
```

## 9. Edge Cases

| Case | Behavior |
|------|----------|
| Empty memories | Return "No project context available yet. You can teach me with the 'remember' tool." |
| Stale cache (TTL expired) | Treat as cache miss, run fresh query |
| Cache hit during re-index | Return cached result (stale but usable) |
| Memory with low importance | Returned last in ranking, may be dropped if max_results is low |
| Duplicate memory | Dedup by content hash before insert |
| Conversation with no activity | Skip summarization (no tool calls, no writes) |
| Very long conversation | Summarization only captures key decisions + files touched, not full transcript |
| Project metadata empty | Auto-generate on first `project_context` call if missing |

## 10. Files to Create

| File | Contents |
|------|----------|
| `Services/Memory/MemoryStore.swift` | SQLite CRUD for project_memory.sqlite |
| `Services/Memory/MemoryRetriever.swift` | Query + ranking logic |
| `Services/Memory/ConversationSummarizer.swift` | Post-chat summary generation |
| `Services/Memory/SearchCacheManager.swift` | TTL-based cache with SQLite backend |
| `Services/Memory/ProjectMetadataGenerator.swift` | One-time metadata generation |
| `Services/Memory/ProjectContextTool.swift` | AITool protocol for project_context |
| `Services/Memory/ProjectContextTool+v2.swift` | ToolDefinition for project_context |
| `Services/Memory/RememberTool.swift` | AITool protocol for remember |
| `Services/Memory/RememberTool+v2.swift` | ToolDefinition for remember |

## 11. Files to Migrate / Move

| From | To | Notes |
|------|----|-------|
| `Services/Index/Memory/MemoryManager.swift` | `Services/Memory/MemoryManager.swift` | Move, keep as-is |
| `Services/Index/Memory/MemoryEmbeddingGenerator.swift` | `Services/Memory/MemoryEmbeddingGenerator.swift` | Move, keep as-is (optional vector support) |
| `Services/Index/Database/DatabaseMemoryManager.swift` | `Services/Memory/MemoryStore.swift` | Merge into MemoryStore |
