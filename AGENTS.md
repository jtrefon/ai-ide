# AGENTS.md

## Commands

```sh
./run.sh build            # Full Xcode build
./run.sh test             # Unit tests (skips UI-heavy suites)
./run.sh test SuiteName   # Single suite filter (e.g. LogCoordinatorTests)
./run.sh harness          # Headless integration tests
./run.sh e2e              # XCUITest suites
./run.sh clean            # rm -rf .build .build-tests + xcodebuild clean
```

Build runs via `xcodebuild`, not `swift build`. Scheme = `osx-ide`. Derived data: `.build/` for app, `.build-tests/` for tests.

Package resolution: `xcodebuild -resolvePackageDependencies -project osx-ide.xcodeproj`.

## Architecture

- **Entrypoint**: `osx_ideApp.swift:32` — `OSXIDEApp` with `@NSApplicationDelegateAdaptor AppDelegate`.
- **DI container**: `DependencyContainer.swift` — `@MainActor` class, creates all services, wires EventBus.
- **EventBus**: `Core/EventBus.swift` — central pub/sub via Combine `PassthroughSubject`. Typed events, dispatched by type name. Subscribers receive on `DispatchQueue.main`.
- **Two AI pipelines**: local (MLX 4B model for inline completion) + cloud (OpenRouter via `ConversationOrchestrator` for agentic work).
- **Vector store**: FAISS via C bridge (`Services/VectorStore/CFAISSWrapper/` + `libfaiss_full.a`). Metadata in JSON sidecar.
- **Project state dir**: `.ide/` by default, overridable via `IDE_DIR_NAME` env var. Houses logs, index, vector store, chat history, plans, checkpoints.

### Key patterns

| Pattern | Where |
|---|---|
| `actor` for isolated services | `VectorStoreService`, `ConversationLogStore`, `AppLogger` |
| `@unchecked Sendable` for Combine bags | `LogCoordinator`, `VectorStoreEmbeddingCoordinator` |
| Singletons via `shared` | `AppLogger.shared`, `ConversationLogStore.shared` |
| Event types conform to `Event` protocol | `Core/EventBus.swift:13` |
| `@MainActor` on pipeline classes | `ToolLoopHandler`, `FinalResponseHandler`, `AIToolExecutor` |
| Codegen: none. SPM packages under `Packages/` | `SyntaxHighlighting`, `Terminal` |

### .ide directory structure

```
.ide/
├── chat/                 # Conversation history
├── checkpoints/          # Agent checkpoints
├── index/                # Codebase SQLite (FTS5 + symbols)
├── logs/
│   └── conversations/    # NDJSON per conversation (conversation.ndjson + executions.ndjson)
├── orchestration/        # Run snapshots
├── plans/                # Task plans
├── staging/              # Staged diffs
├── vector_store/         # FAISS index + metadata.json
├── index_exclude         # Exclude patterns file
└── session.json          # UI state
```

### Vector store data flow

```
ContextLogEvent / ToolResultEvent → EventBus
  ├── LogCoordinator → writes NDJSON to .ide/logs/
  └── VectorStoreEmbeddingCoordinator
       ├── buffers user_message, pairs with assistant_message
       ├── generates embedding via HashingMemoryEmbeddingGenerator
       └── stores (vector + SourceReference) in FAISS
```

## Testing

- **Swift Testing** (`import Testing`) used in newer tests (`LogCoordinatorTests`).
- **XCTest** (`import XCTest`) used in older tests (`AIToolExecutorSchedulerTests`).
- Unit tests: `./run.sh test` — skips 6 UI-heavy suites that need AppKit rendering.
- Harness tests: `./run.sh harness` — headless integration, memory-guarded (6GB default).
- Online harnesses (`AgenticHarnessTests` etc.) require `OSX_IDE_RUN_ONLINE_HARNESS=1` and **must not run in parallel** (provider rate limits).
- Test config env vars: `ALLOW_EXTERNAL_APIS`, `USE_MOCK_SERVICES`, `SWIFT_ENABLE_EXPLICIT_MODULES`.

## Gotchas

- **LSP false positives**: sourcekit-lsp frequently reports "Cannot find type 'X' in scope" for cross-module types. The actual build (`./run.sh build`) is the source of truth.
- **FAISS**: linked as a static library (`libfaiss_full.a`). The C bridge (`CFAISSWrapper.c`) wraps `faiss_c.h`. No Swift Package Manager dependency.
- **xcodebuild package resolution** sometimes fails on first attempt for `SwiftJinja/OrderedCollections`. Running `xcodebuild -resolvePackageDependencies` fixes it.
- **Indexer uses SQLite raw** (no GRDB/CoreData). Schema in `DatabaseManager.swift`. FTS5 for full-text search.
- **Syntax highlighting**: tree-sitter via `Packages/SyntaxHighlighting`. No more token-based highlighting.
- **Some test suites take 3+ minutes** (`AIToolExecutorSchedulerTests.testWriteToolsSerializeByPath`).
