# Architecture Documentation

## Overview

osx-ide is a native macOS IDE with dual AI pipelines — a local pipeline powered by a 4B MLX model for instant, private daily coding, and a cloud pipeline powered by OpenRouter for agentic, multi-file work at scale. The two pipelines share an editor and infrastructure but are architecturally independent.

## Core Architecture

### Dual-Pipeline Design

```
┌──────────────────────────────────────────────────────────────────┐
│                        UI LAYER                                  │
│  SwiftUI Views · AppKit Components · NSTextView · Terminal      │
│  File Tree · Command Palette · Panels · Settings                 │
├──────────────────────────────────────────────────────────────────┤
│                        CORE LAYER                                │
│  EventBus · CommandRegistry · DependencyContainer · Models       │
├──────────────────────────────────────────────────────────────────┤
│                     SHARED SERVICES                              │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ CodebaseIndex│  │ Tool Impls   │  │ FileSystem · Terminal  │ │
│  │ SQLite, FTS5, │  │ (AITool      │  │ Session · Settings    │ │
│  │ symbols,      │  │  protocol)   │  │ EventBus              │ │
│  │ embeddings    │  │              │  │                        │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
├──────────────────────┬───────────────────────────────────────────┤
│   LOCAL AI PIPELINE  │           CLOUD AI PIPELINE               │
│                      │                                           │
│ ┌──────────────────┐ │ ┌──────────────────────────────────────┐ │
│ │ LocalInteraction │ │ │ ConversationOrchestrator             │ │
│ │ Service          │ │ │ ┌──────────┐                         │ │
│ │ ─ Direct LLM     │ │ │ │ Planner  │                         │ │
│ │   call to 4B MLX │ │ │ └────┬─────┘                         │ │
│ │ ─ No orchestrate │ │ │      v                               │ │
│ │ ─ No tool loop   │ │ │ ┌──────────┐  ┌──────────────┐     │ │
│ │ ─ No RAG injection│ │ │ │ Worker   │→│ Tool Executor│     │ │
│ │ ─ Simpler context │ │ │ │(ToolLoop)│  │ (AITool impls)│     │ │
│ └──────────────────┘ │ │ └────┬─────┘  └──────────────┘     │ │
│                      │ │      v                               │ │
│ ┌──────────────────┐ │ │ ┌──────────┐                         │ │
│ │ InlineCompletion │ │ │ │ QAReview │                         │ │
│ │ Engine            │ │ │ └────┬─────┘                         │ │
│ │ ─ 4B MLX <100ms  │ │ │      v                               │ │
│ │ ─ Ghost text      │ │ │ ┌──────────┐                         │ │
│ │ ─ Cache + rank    │ │ │ │ Final    │                         │ │
│ └──────────────────┘ │ │ └──────────┘                         │ │
│                      │ └──────────────────────────────────────┘ │
│ ┌──────────────────┐ │ ┌──────────────────────────────────────┐ │
│ │ InlinePopover    │ │ │ RAGEngine                             │ │
│ │ ─ Cursor-anchored│ │ │ ─ Retrieval + ranking                │ │
│ │ ─ File-scoped QA │ │ │ ─ Context injection (cloud only)     │ │
│ │ ─ Quick explain   │ │ │ ─ Evidence fusion                   │ │
│ └──────────────────┘ │ └──────────────────────────────────────┘ │
└──────────────────────┴───────────────────────────────────────────┘
```

### Key Architectural Decision: Two Separate AI Pipelines

Local and cloud pipelines share ZERO AI execution code. The only shared components are:

| Shared Component | Used By | How |
|---|---|---|
| CodebaseIndex | Both | Read-only queries for context and search |
| Tool implementations (AITool protocol) | Cloud only | Executed by ToolLoopHandler |
| FileSystemService | Both | File I/O for context and tool results |
| TerminalService | Both | Terminal operations |
| EventBus | Both | Events for telemetry and UI updates |
| CommandRegistry | Both | Commands triggered by AI or user |
| DependencyContainer | Both | DI for shared services |

## Component Architecture

### 1. CodebaseIndex (`Services/Index/`)

The shared knowledge foundation. An SQLite database with FTS5 full-text search, symbol extraction, and embedding-based semantic search.

**Key capabilities:**
- File indexing with content hashing (skip unchanged files)
- FTS5 full-text search with ranking
- Symbol extraction (Swift, TypeScript, JavaScript, Python, regex fallback)
- Semantic search via embedding vectors (O(n) currently, target: ANN)
- File watching with intelligent debouncing

**Consumers:**
- Local pipeline: semantic search, symbol resolution for inline features
- Cloud pipeline: RAG retrieval, tool-backed search (index_find_files, index_search_text, etc.)
- UI: workspace search, symbol search

**Database schema:**
- `resources` — one row per indexed file (path, language, hash, summary)
- `resources_fts` — FTS5 virtual table for full-text search
- `symbols` — extracted symbols with location and kind
- `code_chunks` — overlapping chunks with embedding vectors

### 2. Local AI Pipeline (`Services/LocalPipeline/`)

A minimal, fast path for the 4B MLX model.

**Components:**

```
LocalInteractionService
  ─ receives: user input + optional explicit context (current file, selection)
  ─ optionally queries CodebaseIndex for relevant context
  ─ calls: LocalModelProcessAIService (4B MLX)
  ─ returns: text response

InlineCompletionEngine
  ─ triggered by: text change events (debounced)
  ─ builds: completion context (prefix, suffix, scope)
  ─ optionally: retrieves context from CodebaseIndex
  ─ calls: 4B MLX model for inline completion
  ─ renders: ghost text in NSTextView
  ─ accepts: Tab, dismisses: Esc

InlinePopoverService
  ─ triggered by: Cmd+I / selection context menu
  ─ reads: current selection, file contents
  ─ shows: floating popover anchored to cursor
  ─ supports: explain, refactor, quick transform, find similar
  ─ calls: 4B MLX model
```

**What the local pipeline does NOT have:**
- No orchestration graph (no Planner, Worker, QA nodes)
- No tool loop (no iterative tool execution)
- No RAG context injection (context is explicitly requested, not prepended)
- No planning or strategy synthesis
- No conversation folding or memory management

### 3. Cloud AI Pipeline (`Services/CloudPipeline/`)

A full-featured, graph-based orchestration pipeline for agentic coding with cloud models via OpenRouter.

**Components:**

```
ConversationOrchestrator
  ─ entry point for cloud AI interactions
  ─ builds the execution graph:
      StrategicPlanning → TacticalPlanning → Dispatcher
        → ToolLoop (iterative) → BranchReview
          → (optional) QAToolOutputReview → QAQualityReview
        → FinalResponse

RAGEngine
  ─ only used in cloud pipeline
  ─ retrieves codebase context via CodebaseIndex
  ─ classifies intent (bugfix, feature, refactor, etc.)
  ─ fuses evidence with ranking (semantic + structural + recency)
  ─ injects as "RAG CONTEXT:" block in cloud requests

ToolLoopHandler
  ─ iterative execution loop with stall detection
  ─ deduplication, mutation tracking, recovery strategies
  ─ max iterations: 50 (configurable)
  ─ only runs for cloud model requests

Tool implementations
  ─ conform to AITool protocol
  ─ shared implementations, NOT shared execution loop
  ─ cloud pipeline executes them via ToolLoopHandler
```

**What the cloud pipeline does NOT do:**
- No inline completion (that's local-only)
- No inline popover Q&A (that's local-only)
- No direct file-level quick transforms (those are local-only)

### 4. AI Router (`Services/AIRouter.swift`)

The component that decides which pipeline handles a given request.

**Routing logic:**

| User Action | Route | Why |
|---|---|---|
| Typing (completion) | Local | Latency-critical, context-limited |
| Cmd+I on selection (explain) | Local | Single file, instant desired |
| Cmd+Shift+I (inline chat) | Local | Cursor-anchored, file-scoped |
| Chat panel message (local mode) | Local | User chose local |
| Chat panel message (cloud mode) | Cloud | User chose cloud |
| Agentic task ("refactor X across project") | Cloud | Needs tools, multi-file |
| Semantic search (Cmd+Shift+F) | CodebaseIndex directly | No AI needed |
| Diagnostics explanation | Local | Single file, instant |

**Explicit user control:**
- Chat panel has a local/cloud toggle per conversation
- Agentic mode toggle enables cloud pipeline for chat
- Completion and inline features are always local
- Future: smart auto-routing based on query complexity

### 5. ConversationManager (`Services/ConversationManager.swift`)

**Planned refactoring target.** Currently a god object managing both pipelines. Will be split into:

```
ConversationManager (simplified router)
  ├── LocalInteractionService (new, simple)
  ├── CloudConversationService (extracted from current manager)
  └── SessionManager (tabs, history, state)
```

### 6. Tool System (`Services/Tools/`)

Individual tool implementations conforming to `AITool` protocol. These are the actual operations (read file, write file, search, execute command, etc.).

**Key design:**
- Tools are shared between pipelines as implementation code
- Only the cloud pipeline executes tools iteratively via ToolLoopHandler
- The local pipeline never invokes tools (too unreliable for 4B model)
- Tools have no knowledge of which pipeline invoked them

## Data Flow

### Local Pipeline: Inline Q&A

```
User selects code → Cmd+I
  → InlinePopoverService.show(for: selection)
    → reads current file from FileEditorService
    → builds prompt: "Explain this code: ..."
    → calls LocalModelProcessAIService.generate(prompt)
    → 4B MLX model responds
  → shows response in cursor-anchored popover
  → user dismisses with Esc
  Total: ~100-300ms
```

### Local Pipeline: Code Completion

```
User types character
  → NSTextView.textDidChange
    → EditorSignalBridge.scheduleAutomaticRequest()
      → InlineCompletionEngine.requestCompletion()
        → CompletionContextAssembler.buildContext() (prefix, suffix, scope)
        → CompletionInferenceService.infer() → 4B MLX model
        → SuggestionRanker.evaluate()
        → publish suggestion
      → CodeEditorTextView.showGhostText(suggestion)
  → User presses Tab → accept
  Total: ~50-150ms
```

### Cloud Pipeline: Agentic Request

```
User types: "Add error handling to all API routes"
  → ConversationManager routes to CloudConversationService
    → ConversationOrchestrator.run()
      → StrategicPlanningNode (creates a plan)
      → TacticalPlanningNode (merges user input into plan)
      → DispatcherNode (sends initial LLM response)
        → model responds with tool calls
      → ToolLoopNode:
        [loop] → execute tool calls → send follow-up → repeat
        → stall detection, mutation tracking, recovery
      → BranchReviewNode (check if branch complete)
      → FinalResponseNode (format summary)
    → response shown in chat panel
  Total: ~5-60s (depending on complexity)
```

## Pipeline Isolation Rules

1. **No shared state** between pipelines beyond what's in shared services. Local and cloud conversations have separate histories, separate contexts, separate caches.

2. **No shared execution code.** Local code path is simple: prompt → model → response. Cloud code path is complex: plan → execute → loop → review → final. They share zero lines of AI execution logic.

3. **RAG is cloud-only.** The local model gets explicit context (current file, selection) — not a RAG-injected context block. If the local model needs codebase context, it's queried explicitly from the index.

4. **Tools are cloud-only.** The local model never invokes tools. It would be unreliable and slow. Tools are for cloud models with sufficient reasoning capability.

5. **Inline completion is local-only.** Never route a completion request to the cloud. The latency would defeat the purpose.

## Service Layer Responsibilities

### Shared (non-AI) Services

| Service | Responsibility |
|---|---|
| `EventBus` | Typed event publish/subscribe |
| `CommandRegistry` | Command registration and execution |
| `DependencyContainer` | DI container (migrate singletons here) |
| `FileSystemService` | File I/O operations |
| `WorkspaceService` | Project management, path resolution |
| `FileEditorService` | Open file state management |
| `TerminalService` | Terminal emulation |
| `SessionService` | Layout persistence |
| `ErrorManager` | Error logging and reporting |
| `PowerManagementService` | Prevent sleep during AI activity |
| `SettingsStore` | User preferences (UserDefaults + Keychain) |

### Local Pipeline Services

| Service | Responsibility |
|---|---|
| `LocalInteractionService` | Direct 4B model interaction for Q&A |
| `InlineCompletionEngine` | Ghost text code completion |
| `InlinePopoverService` | Cursor-anchored assistant |
| `LocalModelProcessAIService` | MLX model loading and inference |

### Cloud Pipeline Services

| Service | Responsibility |
|---|---|
| `ConversationOrchestrator` | Graph-based orchestration |
| `RAGEngine` | Codebase context retrieval and injection |
| `ToolLoopHandler` | Iterative tool execution loop |
| `QAReviewHandler` | Quality assurance review |
| `OpenRouterAIService` | Cloud model API client |
| `PlanningService` | Strategic/tactical plan synthesis |

## Directory Structure (Target)

```
osx-ide/
├── Core/                     # Shared infrastructure
│   ├── EventBus/
│   ├── CommandRegistry/
│   ├── DependencyContainer/
│   ├── StandardCommands.swift
│   └── Models/
├── Components/               # UI components
│   ├── Editor/
│   ├── FileTree/
│   ├── Chat/
│   ├── Terminal/
│   ├── Settings/
│   └── Shared/
├── Services/
│   ├── Index/                # CodebaseIndex (shared)
│   ├── Tools/                # AITool implementations (shared)
│   ├── LocalPipeline/        # Local 4B AI pipeline
│   │   ├── LocalInteractionService.swift
│   │   ├── InlinePopoverService.swift
│   │   └── (trims existing InlineCompletion/)
│   ├── CloudPipeline/        # Cloud AI pipeline
│   │   ├── ConversationOrchestrator/
│   │   ├── RAGEngine/
│   │   ├── ToolLoopHandler.swift
│   │   └── QAReviewHandler.swift
│   ├── LocalModels/          # MLX model management
│   ├── OpenRouterAI/         # OpenRouter API client
│   ├── Session/
│   ├── Errors/
│   ├── Logging/
│   └── Events/
├── Highlighting/
├── Markdown/
└── Utilities/
```

## Migration Path from Current Architecture

The current codebase has all services intertwined in `Services/` with no local/cloud separation. Migration to the target architecture happens in phases:

**Phase 1 — Cut (delete misaligned code):**
- Delete `Services/Index/Memory/` (overengineered)
- Delete `Services/Index/Scoring/` (unclear value)
- Delete `Services/Index/AIEnrichment.swift` (expensive, unclear ROI)
- Remove RAG injection from `AIInteractionCoordinator` (make cloud-only)

**Phase 2 — Isolate (separate pipelines):**
- Extract `LocalInteractionService` from current `ConversationManager`
- Rename current `Services/ConversationFlow/` → `Services/CloudPipeline/`
- Move `InlineCompletion/` under `LocalPipeline/`
- Create `AIRouter` for pipeline routing

**Phase 3 — Simplify local path:**
- Remove orchestration from local path
- Remove tool loop from local path
- Simplify `ConversationManager` to a router + two service backends

**Phase 4 — Polish:**
- Finalize directory structure
- Fix inline completion latency with 4B model
- Fix cloud orchestration bugs
- Add inline popover
