# v2 Search + RAG Decomposition — Product Spec

## 1. Problem Statement

The current `CodebaseIndex` system has three problems:

**A. Slow indexing.** Embedding generation for code chunks adds 15-45 minutes to a full re-index. The original symbol-only index took 3-8 seconds.

**B. Tool confusion for the LLM.** There are 14 search-related tools (`search_project`, `find_file`, `grep`, `find`, `index_search_text`, `index_search_symbols`, `index_find_files`, `index_list_files`, `index_read_file`, `web_search`, `web_browse`, `get_project_structure`, `index_list_memories`, `index_add_memory`). The LLM doesn't know which to pick. Prompt guidance says "always use search_project first" but the other tools remain available.

**C. Fragile RAG pipeline.** The `CodebaseIndexRAGRetriever` + `RAGEvidenceFusionRanker` uses 6 hand-tuned weights across 4 evidence sources. This is hard to debug, hard to tune, and adds latency without clear evidence of value.

## 2. Solution

Split into two independent systems:

### System A: `search_code` (replaces `search_project`, `find_file`, `grep`, and all `index_*` tools)

- Pure SQLite: `resources` + `symbols` + FTS5
- No embeddings, no chunks, no vectors, no HNSW
- Indexes in seconds, not minutes
- Single tool with clean parameters

### System B: `project_memory` (replaces the RAG pipeline, memories, chat context)

- Stores project metadata, agent memories, chat summaries, search cache
- Optional vector search (sqlite-vec) for memory retrieval
- No code indexing — only agent-level knowledge
- Two tools: `project_context` (retrieve) and `remember` (store)

## 3. Success Criteria

| Criterion | Measurement | Current | Target |
|-----------|-------------|---------|--------|
| Full re-index time | Time to index 10K file project | 15-45 min | < 10 sec |
| Incremental re-index | Time after saving 1 file | 5-30 sec | < 50 ms |
| Search response time | P95 latency for `search_code("DataManager")` | N/A (varies) | < 100 ms |
| Tool count for code search | Number of tools the LLM sees for code lookup | 14 | 1 (`search_code`) |
| Agent memory recall | Can agent recall a fact stored 10 conversations ago | N/A | Yes |
| RAG context injection | Context added to LLM prompt per turn | ~5K chars avg | Same or less, higher relevance |

## 4. Out of Scope

- Web search (`web_search`, `web_browse`) — these are independent tools, not part of code search or memory. Keep as-is.
- Terminal execution — unrelated.
- File reading/writing tools — unrelated.
- The `ToolRegistrar` / new `ToolDefinition` system migration — that's a parallel effort. These designs work with both old `AITool` and new `ToolDefinition`.

## 5. User Stories

### Story 1: Developer asks "Where is DataManager?"

```
User: "Where is the DataManager class?"
Agent calls: search_code(query: "DataManager", kind: "class")
Result: DataManager.swift:42
```

### Story 2: Developer asks about project architecture

```
User: "What architecture does this project use?"
Agent calls: project_context(query: "architecture")
Result: "This project uses SwiftUI + MVVM. Network calls go through NetworkService."
```

### Story 3: Agent learns from a bug fix

```
After a conversation where the user fixed a SQLite ghost commit bug:
System auto-generates summary → remember(content: "...", category: "bugfix")
Next conversation about ghost commits → project_context recalls it
```

### Story 4: Agent searches cached results

```
User asks about DataManager for the second time:
First time: search_code(query: "DataManager") → result cached
Second time: project_context(query: "DataManager") returns cached result instantly
```

## 6. Non-Goals

- Replacing the LLM's native context window
- Building a general-purpose vector database
- Supporting multi-project memory (single project only)
- Real-time collaborative memory (single user)
- Memory expiration/GC beyond TTL for search cache
