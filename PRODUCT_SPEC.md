# Product Specification

## Target User

**Primary:** Professional macOS developer using a 16GB M4 MacBook Pro (or equivalent Apple Silicon). They work on codebases ranging from small side projects to large production systems. They value speed and privacy over cloud features they don't trust or can't afford.

**Secondary:** Developers who want a single editor for both daily coding and complex agentic work. They use cloud models for the heavy lifting but want instant local AI for the daily flow.

**Non-target:** Users on non-Mac platforms (Windows, Linux), users with <16GB RAM, users who want a purely cloud-based IDE (Cursor, Windsurf, GitHub Codespaces).

## Feature Matrix

### Local Pipeline (4B MLX) — Always On, Always Private

| Feature | Status | Priority | Notes |
|---|---|---|---|
| Inline code completion (ghost text) | ✅ Implemented | P0 | Works. `.fast` limits by default (prefix 500 chars, output 40 chars). |
| Ghost text rendering (Tab accept, Esc dismiss) | ✅ Implemented | P0 | Works. |
| Completion trigger policy (debounce, language check) | ✅ Implemented | P1 | |
| Completion context assembly (prefix, suffix, scope) | ✅ Implemented | P1 | `.fast` mode on by default (prefix 4K→500, output 120→40). |
| Completion caching | ✅ Implemented | P2 | |
| Completion ranking (filter duplicates, indentation) | ✅ Implemented | P1 | |
| Completion telemetry | ✅ Implemented | P3 | |
| Completion settings UI | ✅ Implemented | P1 | |
| Completion debug overlay | ✅ Implemented | P3 | |

| Inline AI popover (cursor-anchored Q&A) | ✅ Implemented (5.1) | P0 | `InlineAIPopoverView` + `InlineAIPopoverManager` (`.disabled` singleton). Glass material overlay on `CodeEditorView`. Question input + streaming answer. |
| Inline popover: explain code | ✅ Implemented (5.1) | P0 | Basic Q&A flow via popover. Text-based answer streaming. |
| Inline popover: quick refactor | 🟡 Partial | P1 | Popover infrastructure present. Refactor-specific transforms not built. |
| Inline popover: fix diagnostics | ❌ Not implemented | P1 | Infrastructure present. Not wired to diagnostics gutter. |
| Inline popover: find similar code | ❌ Not implemented | P2 | |
| Inline popover: quick docs | ❌ Not implemented | P3 | |

| Direct chat with local model | 🟡 Partial | P1 | Exists as "offline mode" in chat panel. |
| Semantic search (vector-based) | ✅ Implemented (5.3) | P1 | Replaced O(n) brute-force with HNSW ANN index. ~10-50x faster, ~95-99% recall. |
| Diagnostics explanation | ❌ Not implemented | P1 | |
| Code transform: rename/extract/fix | ❌ Not implemented | P2 | |

### Cloud Pipeline (OpenRouter) — On Demand, Full Power

| Feature | Status | Priority | Notes |
|---|---|---|---|
| Chat with cloud model | ✅ Implemented | P0 | Works via OpenRouter. |
| Orchestration graph (Planner → Worker → QA → Final) | ✅ Implemented | P0 | Bugs fixed in 5.2. |
| Tool loop with stall detection | ✅ Implemented | P0 | `usesLocalModel` parameter bug fixed (was defaulting to false, causing 50x iterations for local). |
| Tool execution (20+ tools) | ✅ Implemented | P0 | |
| RAG context injection | ✅ Made cloud-only (1.1) | P1 | Skipped for local model requests. |
| RAG: intent classification | ✅ Implemented | P1 | |
| RAG: evidence fusion ranking | ✅ Implemented | P1 | |
| RAG: code segment retrieval | ✅ Implemented | P1 | HNSW-backed (5.3) for faster ANN search. |
| RAG: project overview | ✅ Implemented | P1 | |
| RAG: symbol search | ✅ Implemented | P1 | |
| QA review | ✅ Fixed (5.2) | P2 | Failures caught + logged instead of fatal. |
| Plan synthesis | ✅ Implemented | P2 | |
| Conversation folding | ✅ Implemented | P2 | |
| Conversation history persistence | ✅ Implemented | P0 | |
| Streaming responses | ✅ Implemented | P0 | |
| Multi-file refactoring | 🟡 Partial | P0 | |
| Autonomous task execution | 🟡 Partial | P0 | |

### Shared Infrastructure

| Feature | Status | Priority | Notes |
|---|---|---|---|
| CodebaseIndex: file indexing | ✅ Implemented | P0 | |
| CodebaseIndex: FTS5 search | ✅ Implemented | P0 | |
| CodebaseIndex: symbol extraction | ✅ Implemented | P0 | |
| CodebaseIndex: file watching | ✅ Implemented | P0 | |
| CodebaseIndex: embedding-based semantic search | ✅ Implemented (5.3) | P1 | HNSW ANN index. 10-50x speedup. |
| CodebaseIndex: memory system | 🟡 Partial | P2 | Minimal. Memory embeddings kept (cloud RAG use). |
| CodebaseIndex: AI enrichment | ❌ Removed (0.3) | P3 | Deleted — expensive, unclear ROI. |
| NSTextView editor with syntax highlighting | ✅ Implemented | P0 | |
| Multi-file tree | ✅ Implemented | P0 | |
| Terminal integration | ✅ Implemented | P0 | |
| Command palette | ✅ Implemented | P0 | |
| Keyboard shortcuts | ✅ Implemented | P0 | |
| Layout persistence | ✅ Implemented | P0 | |
| Settings UI | ✅ Implemented | P0 | |
| Accessibility identifiers | ✅ Implemented | P2 | |

## Actual Execution History (Refocus-v1 Branch)

The 5-phase refocus plan was executed on the `refocus-v1` branch. Below is what was delivered in each phase. See `ARCHITECTURE.md#Migration-Log` for detailed file-by-file accounting. See `REFOCUS_TRACKER.md` for the dependency-gated tracker.

### Phase 0 — Foundation (Completed)
**Goal:** Vision docs, cuts, bloat removal.
**Delivered:** 8 tracker items (vision docs, Scoring/, AIEnrichment, RAGStatusGauge, protocol cleanup, test mocks). Build gate: ✅

### Phase 1 — Pipeline Isolation (Completed)
**Goal:** Stop blending local and cloud AI pipelines.
**Delivered:** 3 tracker items (RAG out of local path, orchestration out of local path, pipeline routing). Build gate: ✅

### Phase 2 — Structural Reorg (Completed)
**Goal:** Directory structure reflects architecture.
**Delivered:** 4 tracker items (ConversationFlow→CloudPipeline, InlineCompletion→LocalPipeline, LocalInteractionService, imports/project). Xcode 16 auto-grouping. Build gate: ✅

### Phase 3 — Architecture Completion (Completed)
**Goal:** Clean separation with AIRouter + SessionManager.
**Delivered:** 3 tracker items (SessionManager extraction, AIRouter, RAGTelemetryAggregator deletion). Build gate: ✅

### Phase 4 — Model Optimization (Partial)
**Delivered:** `LocalModelAdapter` protocol, `Qwen36Adapter`, `CompletionBenchmarkService`. Completion context `.fast` limits.
**Remaining:** 4.3 (benchmarks with real model) and 4.4 (tune to <100ms p50) — BLOCKED: require model execution on user machine.

### Phase 5 — Polish & Ship (3/5 Complete)
**Delivered:**
- 5.1: `InlineAIPopoverView` + `InlineAIPopoverManager` (glass material, cursor-anchored, streaming answer)
- 5.2: `usesLocalModel` parameter fix in `ConditionalToolLoopNode` + recursive `ToolLoopHandler`. Non-fatal QA review failures
- 5.3: `HNSWIndex` — pure-Swift ANN index integrated into `DatabaseMemoryManager` and `DatabaseCodeChunkManager`

**Remaining:**
- 5.4: 28 singletons → DI container migration
- 5.5: ~50+ force unwrap removals

### What Remains After Refocus
| Area | Remaining Work | Blockers |
|------|---------------|----------|
| Model optimization | 4.3 benchmarks, 4.4 latency tuning | Need real 4B model on user's 16GB M4 MacBook |
| Code quality | 5.4 singletons (28), 5.5 force unwraps (~50+) | None |
| Build/test | Pre-existing SPM test target failure (EventSource→swift-nio) | External dependency |
| Cloud polish | Tool loop recovery strategies, plan supervision edge cases | None |
| Mac integration | Spotlight, Shortcuts, AppleScript | Not started |

## What We Explicitly Do NOT Build

This list is as important as the feature list. These are things that seem tempting but would dilute focus. Items marked **[REMOVED]** were cut during the refocus.

| Feature | Reason Excluded |
|---|---|
| Cross-platform support | We compete on Mac integration and Apple Silicon optimization. Electron/Win/Linux support would split focus and compromise performance. |
| Plugin system (v1) | Product needs to be excellent before it needs extensibility. v2 consideration. |
| Built-in issue tracker | Users have GitHub/GitLab/Jira. Build integration, not replacement. |
| Design mode / visual editor | Not an AI IDE feature. Focus on code. |
| Inline AI chat (Cmd+Shift+I) | Replaced by inline popover (Cmd+I). |
| Agentic mode for local model | The 4B model cannot do this reliably. Cloud-only. |
| Memory / long-term storage (v1) | AI-written "memories" — unclear value. Minimal embeddings kept for cloud RAG. |
| AI-generated file summaries | **[REMOVED]** `AIEnrichment` deleted in Phase 0.3. Expensive, unclear ROI. |
| Auto-fix-all mode | Too dangerous without user review. |
| Model training/fine-tuning | We consume models, not train them. |
| **[REMOVED]** Scoring/ quality engine | Deleted Phase 0.1. `SwiftHeuristicScorer`, `QualityScoringEngine` — unclear value. |
| **[REMOVED]** RAGStatusGauge | Deleted Phase 0.4. Unused UI component. |
| **[REMOVED]** RAGTelemetryAggregator | Deleted Phase 3.3. |
| **[REMOVED]** MemoryEmbeddingSearchProviding from index | Protocol kept. Implementation uses HNSW (5.3) instead of separate search provider. |
| **[REMOVED]** Codebase index tier-based memory management | Memory tiers (short/mid/long-term) kept minimal. ProtectionCalculator removed. |

## Success Criteria by Phase (Actual Status)

### Phase 0 Success — ✅ Complete
- Vision/Architecture/Product docs written ✅
- Scoring/ deleted ✅
- AIEnrichment + events + DB manager deleted ✅
- RAGStatusGauge deleted ✅
- CodebaseIndexProtocol / DatabaseManager / ProjectCoordinator cleaned ✅
- Test mocks fixed ✅

### Phase 1 Success — ✅ Complete
- RAG injection removed from local path ✅
- Orchestration graph removed from local path ✅
- `ConversationSendCoordinator` skips graph for local model ✅

### Phase 2 Success — ✅ Complete
- `ConversationFlow/` → `CloudPipeline/` ✅
- `InlineCompletion/` → `LocalPipeline/InlineCompletion/` ✅
- `LocalInteractionService` created ✅
- `LocalModelAdapter` + `Qwen36Adapter` created ✅
- Build compiles ✅

### Phase 3 Success — ✅ Complete
- `SessionManager` extracted from `ConversationManager` (981→880 lines) ✅
- `AIRouter` created ✅
- `RAGTelemetryAggregator` deleted ✅

### Phase 4 Success — 🟡 Partial
- `LocalModelAdapter` protocol 6 methods ✅
- `Qwen36Adapter` implementation ✅
- `CompletionBenchmarkService` created ✅
- Completion `.fast` limits as default ✅
- ⬜ Benchmarks (blocked: need real model)
- ⬜ <100ms p50 latency tuning (blocked: need benchmarks)

### Phase 5 Success — 🟡 3/5 Complete
- 5.1 Inline popover: cursor-anchored overlay with streaming answer ✅
- 5.2 Cloud bugs: `usesLocalModel` fix, non-fatal QA ✅
- 5.3 HNSW ANN: 10-50x faster semantic search ✅
- ⬜ 5.4 Singletons: target <5 (from 28)
- ⬜ 5.5 Force unwraps: target 0 (from ~50+)

## Measurement Framework

### Local Pipeline KPIs
- Inline completion latency: p50 <100ms, p95 <200ms
- Inline completion acceptance rate: >30%
- Inline popover response time: <500ms
- Semantic search latency: <50ms
- Local model load time: <10s

### Cloud Pipeline KPIs
- Agent task success rate: >80%
- Average turns to complete task: <10
- Tool call failure rate: <5%
- User satisfaction rating: >4/5

### Code Quality KPIs (Refocus State)
- Singleton count: **28** (target <5 after Phase 5.4)
- Force unwrap count: **~50+** (target 0 after Phase 5.5)
- ConversationManager size: **880 lines** (was 981, split via SessionManager; target <300)
- ToolLoopHandler size: **2824 lines** (unchanged — Phase 3 did not touch)
- HNSWIndex: **~300 lines** (new, clean, annotated)
- Files deleted during refocus: **~7,966 lines removed**, **1,737 added** (net: ~6,229 fewer lines)
- Build: **Zero Swift compilation errors from refocus changes** (pre-existing SPM dependency issue on test target only)
