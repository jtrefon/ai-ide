# Event-Driven Logging & Embedding Architecture

## Motivation

The app produces rich contextual data — tool call outputs, web search results, browser content, terminal output, file content, sub-agent results — but there is no unified pipeline to capture, persist, and embed this data for future RAG retrieval.

### Current Pain Points

1. **Scattered logging** — `ConversationLogStore`, `ExecutionLogStore`, `AIToolTraceLogger`, `AppLogger` are called independently from different sites. Adding a new data source requires touching multiple log stores.

2. **Embedding only watches `conversation.ndjson`** — `VectorStoreEmbeddingCoordinator` monitors FS changes for `conversation.ndjson` but NOT `executions.ndjson` or other log files. Tool execution content, web results, console output are never embedded.

3. **Data leaves memory twice** — components write to disk (NDJSON), then the embedding coordinator reads from disk. Both the log store and the embedding coordinator parse the same NDJSON format independently.

4. **No typed contract for contextual data** — tool results, web content, terminal output are passed to the LLM as unstructured text in conversation history. They are not extractable as structured records for future retrieval.

## Proposed Architecture

```
                     EventBus (central nervous system)
                     ┌──────────────────────────────────────┐
                     │                                      │
  ┌──────────┐  pub  │  ┌──────────────────────────────┐    │  sub  ┌──────────────────┐
  │ Tool     │──────→│  │                              │    │──────→│ LogCoordinator    │
  │ Executor │       │  │  ContextLogEvent              │    │       │ (writes NDJSON)   │
  └──────────┘       │  │  TerminalOutputEvent          │    │       └──────────────────┘
                     │  │  FileContentEvent             │    │
  ┌──────────┐  pub  │  │  ToolResultEvent              │    │  sub  ┌──────────────────┐
  │ Terminal │──────→│  │  WebSearchResultEvent         │    │──────→│ Embedding         │
  │ Session  │       │  │  SubagentOutputEvent          │    │       │ Coordinator       │
  └──────────┘       │  │                              │    │       │ (→ FAISS)         │
                     │  └──────────────────────────────┘    │       └──────────────────┘
  ┌──────────┐  pub  │                                      │
  │ Web      │──────→│                                      │
  │ Search   │       └──────────────────────────────────────┘
  └──────────┘
```

### Principle

**One publisher, one event type per data source. Two subscribers — one for persistence, one for embedding.** No component calls a log store or an embedding API directly. All contextual data flows through typed EventBus events.

## Component Map

### Event Types

| Event | Payload | Produced By | Consumers |
|---|---|---|---|
| `ContextLogEvent` | `source`, `content`, `metadata: [String: String]` | Any component with contextual data | LogCoordinator, EmbeddingCoordinator |
| `TerminalOutputEvent` | `sessionId`, `output`, `timestamp` | TerminalSession | LogCoordinator, EmbeddingCoordinator |
| `FileContentEvent` | `url`, `content`, `language` | FileEditorService | LogCoordinator (optional) |
| `ToolResultEvent` | `toolName`, `input`, `output`, `duration` | AIToolExecutor | LogCoordinator, EmbeddingCoordinator |
| (future) `WebSearchResultEvent` | `query`, `results: [title:url:snippet]` | WebSearchTool | LogCoordinator, EmbeddingCoordinator |

### Subscribers

#### LogCoordinator
- **Single subscriber** that replaces all direct calls to `ConversationLogStore.append()`, `ExecutionLogStore.append()`, `AIToolTraceLogger.log()`.
- Writes NDJSON to the appropriate `.ide/logs/` subdirectory based on event type.
- Guarantees every contextual data point is persisted — no data source can bypass logging.

#### EmbeddingCoordinator
- Receives the same typed events in memory.
- Extracts content, generates embeddings via `HashingMemoryEmbeddingGenerator`.
- Stores vector + reference in FAISS index.
- No file I/O — operates on the event payload directly.

### Producers

Existing components stop calling log stores directly and instead publish events:

**Before:**
```swift
// AIToolExecutor+Logging.swift
await ConversationLogStore.shared.append(conversationId: id, type: "tool.execute_success", data: [...])
await ExecutionLogStore.shared.append(ExecutionLogAppendRequest(...))
await AIToolTraceLogger.shared.log(type: "tool.execute_success", data: [...])
```

**After:**
```swift
// AIToolExecutor+Logging.swift
eventBus.publish(ToolResultEvent(name: "web_search", input: query, output: results, duration: 1.2))
// LogCoordinator handles persistence
// EmbeddingCoordinator handles vector storage
```

## Data Flow: Request → Embedding

```
User asks "find the login page"
  └── LLM calls web_search("login page site:example.com")
       └── WebSearchTool executes
            └── publishes ToolResultEvent(name:"web_search", output:"...", ...)
                 ├── LogCoordinator: writes to .ide/logs/conversations/<id>/executions.ndjson
                 └── EmbeddingCoordinator:
                      ├── generates embedding vector
                      ├── stores (vector + reference) in FAISS
                      └── done — no disk read needed
```

The LLM response is a separate path:

```
LLM responds "I found the login page at /auth"
  └── FinalResponseHandler publishes ContextLogEvent(source:"assistant", content:"...")
       ├── LogCoordinator: writes to conversation.ndjson
       └── EmbeddingCoordinator: embeds and stores
```

## Implementation Phases

### Phase 1 — Core Event Types + LogCoordinator ✅

| File | Change | Status |
|---|---|---|
| `Core/ContextLogEvent.swift` | New — single generic event for contextual data | ✅ |
| `Core/ToolResultEvent.swift` | New — typed event for tool execution results | ✅ |
| `Services/Logging/LogCoordinator.swift` | New — subscribes to events, writes NDJSON | ✅ |
| `Services/Logging/ConversationLogStore.swift` | Added `setEventBus()` — publishes `ContextLogEvent` in `append()` | ✅ |
| `AIToolExecutor+Logging.swift` | Publish `ToolResultEvent` alongside existing log calls | ✅ |
| `ConversationManager.swift` | Thread `eventBus` through to `initializeProjectRoot` → `ConversationLogStore.setEventBus()` | ✅ |
| `ConversationLogger.swift` | Accept optional `eventBus` parameter, wire to `ConversationLogStore` | ✅ |

All callers of `ConversationLogStore.shared.append()` (FinalResponseHandler, ToolLoopHandler, QAReviewHandler, ConversationLogger) **automatically** produce `ContextLogEvent` via the instrumented log store. No per-file migration needed.

### Phase 2 — Event-Driven Embedding ✅

| File | Change | Status |
|---|---|---|
| `VectorStoreEmbeddingCoordinator.swift` | Replaced FS-watching with EventBus subscription to `ContextLogEvent` + `ToolResultEvent` | ✅ |
| `VectorStoreEmbeddingCoordinator.swift` | Removed `flush()`, `debounce`, `pendingConversations`, file I/O — embeds immediately on event | ✅ |
| `DependencyContainer.swift` | Removed `projectRoot` and `setEmbeddedTurnCount` from coordinator wiring | ✅ |

The coordinator now receives content in-memory: buffers `chat.user_message`, pairs with `chat.assistant_message`, embeds both and stores in FAISS. No disk read needed. Also embeds tool execution results on `execute_success`/`execute_error`.

### Phase 3 — Additional Data Sources (future)

| Event | Producer | Status |
|---|---|---|
| `TerminalOutputEvent` | TerminalSession — publish on each line | Not yet implemented |
| `FileContentEvent` | FileEditorService — publish on open | Already exists as `FileOpenedEvent`, not yet consumed |
| `WebSearchResultEvent` | GoogleWebSearchTool — publish structured results | Not yet implemented |

### Phase 4 — Deprecate Direct Log Stores / SQLite Migration (future)

- Remove `ConversationLogStore.append()` calls (keep the actor for backward compat)
- Remove `ExecutionLogStore.append()` calls (same)
- Remove `AIToolTraceLogger.log()` calls (same)
- The LogCoordinator becomes the single writer
- **Consideration**: NDJSON files under `.ide/logs/` grow unbounded and may become slow to read/write at scale. A future migration to **SQLite** (one DB per conversation or per project) would provide O(1) lookups, atomic appends, and efficient pruning of old data. The LogCoordinator abstraction makes this swap straightforward — only the writer implementation changes.

## Migration Strategy

**Backward-compatible.** Phase 1 adds the new events and the LogCoordinator alongside the existing log stores. Both paths write to the same NDJSON files. Phase 2 flips one producer at a time from direct-log-store → publish-event. At any point, a producer can be reverted by commenting out the `eventBus.publish()` call and uncommenting the direct log store call.

## Key Decisions

| Decision | Rationale |
|---|---|
| Generic `ContextLogEvent` vs per-source types | Both. A generic event for simple text content, plus typed events (ToolResultEvent) for structured data that consumers need to parse differently |
| EventBus sub instead of FS watch | Avoids disk I/O on the embedding path. Zero latency. Data arrives in memory as typed structs |
| Single LogCoordinator vs per-file loggers | Single subscriber centralizes the write format. Adding a new data source is one event type, not wiring to 3 log stores |
| No debounce on embedding | Contextual events arrive at human timescale (after tool completes). The only debounce needed is for streaming content (tool progress chunks), which can be coalesced by the producer before publishing the final event |

## Files

### New
- `Core/Events/ContextLogEvent.swift`
- `Core/Events/ToolResultEvent.swift`
- `Core/Events/TerminalOutputEvent.swift`
- `Services/Logging/LogCoordinator.swift`

### Modify
- `Services/AIToolExecutor+Logging.swift`
- `Services/ConversationLogger.swift`
- `Services/CloudPipeline/FinalResponseHandler.swift`
- `Services/VectorStore/VectorStoreEmbeddingCoordinator.swift`
- `Services/DependencyContainer.swift`
- `Services/ConversationManager.swift`

### Delete (Phase 4)
- None. Log stores remain as utilities but are no longer called directly from business logic.
