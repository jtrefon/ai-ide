# Refocus Tracker

## Git State

- **Branch:** `refocus-v1`
- **Base:** Created from main branch. 15+ commits ahead.
- **Commits (chronological, newest first):**

| Commit | Phase | Description |
|---|---|---|
| 6f64caad | 5.3 | HNSW index for approximate ANN semantic search (4 new files, 517+ lines) |
| 0d73a512 | 5.2 | Fix cloud pipeline orchestration bugs (usesLocalModel, non-fatal QA) |
| (earlier) | 5.1 | Inline AI popover (InlineAIPopoverView + InlineAIPopoverManager) |
| (earlier) | 4.x | LocalModelAdapter protocol, Qwen36Adapter, CompletionBenchmarkService, .fast limits |
| (earlier) | 3.x | SessionManager extraction, AIRouter, RAGTelemetryAggregator deletion |
| (earlier) | 2.x | Directory renames, LocalInteractionService, Xcode project fix |
| (earlier) | 1.x | Pipeline isolation (RAG out of local, orchestration out of local) |
| (earliest) | 0.x | Vision docs, Scoring/ deletion, AIEnrichment deletion, protocol cleanup, test mocks |

- **Stats:** 94 files changed, 1,737 additions, 7,966 deletions (net: -6,229 lines)

## Phase 0 — Foundation ✅

**Theme:** Vision, cuts, and cleanup.

| # | Item | Impact | Depends On | Status | Key Files Changed |
|---|---|---|---|---|---|
| 0.1 | Write VISION.md, ARCHITECTURE.md, PRODUCT_SPEC.md | 🔑 Sets direction | — | ✅ | New files |
| 0.2 | Delete Scoring/ directory | 🗑️ Removes unreachable code | — | ✅ | `Services/Index/Scoring/` dir deleted |
| 0.3 | Delete AIEnrichment + related events + DB manager | 🗑️ Removes unreachable code | 0.2 | ✅ | `AIEnrichment.swift`, `AIEnrichmentEvent.swift`, `AIEnrichmentDatabaseManager.swift` |
| 0.4 | Delete RAGStatusGauge (unused UI) | 🗑️ Removes dead code | — | ✅ | `Components/RAGStatusGauge.swift` |
| 0.5 | Remove AIEnrichment from CodebaseIndexProtocol + all callers | 🏗️ Cleans protocol surface | 0.3 | ✅ | CodebaseIndexProtocol, CodebaseIndex, DatabaseManager, ProjectCoordinator, DependencyContainer, AppState, osx_ideApp |
| 0.6 | Fix all test mocks + DB stubs | ✅ Maintains green build | 0.5 | ✅ | 6 test files |

**Gate:** Build must compile (no Swift errors from our changes). ✅

**Recovery note:** If a rebase or merge re-introduces AIEnrichment or Scoring references, the compiler will catch them. The protocol surface (`performAIEnrichment`, `aiEnrichedResourceCount`, `averageAIQualityScore`) is removed from `CodebaseIndexProtocol`. `DatabaseManager` stubs return 0/empty for legacy callers.

---

## Phase 1 — Pipeline Isolation ✅

**Theme:** Stop blending local and cloud. RAG and orchestration become cloud-only.

| # | Item | Impact | Depends On | Status | Key Files Changed |
|---|---|---|---|---|---|
| 1.1 | Remove RAG injection from local model path in AIInteractionCoordinator | 🔥 **Highest impact** | 0.5 | ✅ | `AIInteractionCoordinator.SendMessageWithRetryRequest` — skips RAG when `usesLocalModel == true` |
| 1.2 | Remove orchestration graph from local model path | 🔥 **Highest impact** | 1.1 | ✅ | `ConversationSendCoordinator.executeConversationFlow()` — skips orchestration nodes for local, direct LLM call |
| 1.3 | Update routing infrastructure | 🏗️ | 1.2 | ✅ | `SendRequest`, `ConversationSendCoordinator` |

**Gate:** Build must compile. Local model makes direct LLM calls only. Cloud model retains full orchestration + RAG. ✅

**Recovery note:** The local path lands in `ToolLoopHandler.handleToolLoopIfNeeded()` which is unreachable for local (semaphore never fires). Both 1.1 and 1.2 are gated on `usesLocalModel` boolean flowing through the entire request chain.

---

## Phase 2 — Structural Reorg ✅

**Theme:** Directory structure reflects the architecture.

| # | Item | Impact | Depends On | Status | Key Files |
|---|---|---|---|---|---|
| 2.1 | Rename `Services/ConversationFlow/` → `Services/CloudPipeline/` | 🏗️ | 1.2 | ✅ | Directory rename (Xcode 16 auto-grouping) |
| 2.2 | Move `Services/InlineCompletion/` → `Services/LocalPipeline/InlineCompletion/` | 🏗️ | — | ✅ | Directory move |
| 2.3 | Create `LocalInteractionService` | 📦 | 1.2 | ✅ | `Services/LocalPipeline/LocalInteractionService.swift` |
| 2.4 | Fix imports/project references | ✅ | 2.1-3 | ✅ | `DependencyContainer.swift`, `AppState.swift` |

**Note:** Xcode 16 `fileSystemSynchronizedGroups` picks up directory changes automatically — no pbxproj edits required.

---

## Phase 3 — Architecture Completion ✅

**Theme:** Cleanly separate concerns.

| # | Item | Impact | Depends On | Status | Key Files |
|---|---|---|---|---|---|
| 3.1 | Extract `SessionManager` from `ConversationManager` | 🔥 **Major** | 2.3 | ✅ | `ConversationManager.swift` (981→880), `SessionManager.swift` (+210) |
| 3.2 | Create `AIRouter` | 🏗️ | — | ✅ | `Services/AIRouter.swift` |
| 3.3 | Delete `RAGTelemetryAggregator` | 🗑️ | 0.5 | ✅ | `RAGTelemetryAggregator.swift` |

**Gate:** Build must compile. ✅

---

## Phase 4 — Model Optimization (Partial)

**Theme:** Lock in on Qwen3.6 4B 4bit. Thin adapter, deep optimization.

| # | Item | Impact | Depends On | Status | Key Files |
|---|---|---|---|---|---|
| 4.1 | `LocalModelAdapter` protocol | 🏗️ | 2.3 | ✅ | `Services/LocalPipeline/LocalModelAdapter.swift` — 6 methods |
| 4.2 | `Qwen36Adapter` | 🎯 | 4.1 | ✅ | `Services/LocalPipeline/Qwen36Adapter.swift` |
| 4.3 | Benchmarks | 📊 | 4.2 | ⬜ | `CompletionBenchmarkService.swift` exists, needs execution |
| 4.4 | <100ms p50 tuning | 🎯 | 4.3 | ⬜ | `.fast` limits applied; full tuning blocked on benchmarks |

**Note:** `Qwen3.6` has no 4B variant — only 27B (dense) and 35B-A3B (MoE). Adapter targets `mlx-community/Qwen3-4B-Instruct-2507-4bit`. Swap when upstream publishes Qwen3.6 MLX 4bit. Benchmarks (4.3-4.4) blocked on real model execution.

---

## Phase 5 — Polish & Ship (3/5 Complete)

**Theme:** Fix the visible features users actually see.

| # | Item | Impact | Depends On | Status | Key Files |
|---|---|---|---|---|---|
| 5.1 | Inline AI popover (cursor-anchored Q&A) | 🎯 **High** | 3.2 | ✅ | `InlineAIPopoverView.swift`, `InlineAIPopoverManager.swift`, `CodeEditorView.swift` |
| 5.2 | Fix cloud orchestration bugs | 🎯 **High** | 3.1 | ✅ | `ConditionalToolLoopNode.swift`, `ToolLoopHandler.swift`, `QAReviewHandler.swift` |
| 5.3 | ANN semantic search (HNSW) | 🎯 **Medium** | 2.1 | ✅ | `HNSWIndex.swift`, `DatabaseMemoryManager.swift`, `DatabaseCodeChunkManager.swift` |
| 5.4 | Remove 28 singletons | 🏗️ | 3.2 | ⬜ | |
| 5.5 | Remove ~50+ force unwraps | 🏗️ | — | ⬜ | |

### 5.1 Implementation Details
- `InlineAIPopoverManager` — `.disabled` singleton (zero-cost default state). Manages popover lifecycle (show/hide/stream).
- `InlineAIPopoverView` — glass material (`.ultraThinMaterial`) overlay anchored to cursor position. Text input + streaming answer display.
- `CodeEditorView` — overlay integration via `popoverManager` binding.
- **Current limitation:** `.disabled` singleton pattern used instead of proper DI. Clean up in Phase 5.4.

### 5.2 Bug Details
- **Bug 1:** `ConditionalToolLoopNode.handle()` called `handler.handleToolLoopIfNeeded(...)` WITHOUT passing `usesLocalModel`. Defaulted to `false` (50 max iterations for what should have been 5). Fixed by adding `usesLocalModel` parameter.
- **Bug 2:** `ToolLoopHandler.handleToolLoopIfNeeded()` recursively calls itself and was dropping `usesLocalModel`. Same consequence as Bug 1.
- **Bug 3:** `QAReviewHandler.performToolOutputReviewIfNeeded()` and `performQualityReviewIfNeeded()` would throw on QA model failure, aborting the entire conversation send. Fixed by catching + logging warning, returning original response.

### 5.3 HNSW Details
- **`HNSWIndex`** (`Services/Index/Search/HNSWIndex.swift`): Pure-Swift implementation. Not an actor (callers serialize via `DatabaseManager.queue`). Parameters: M=16, efConstruction=200, efSearch=50, mL=1/ln(M). BinaryHeap for O(log n) traversal.
- **Integration:** `DatabaseMemoryManager` holds `[modelId: HNSWIndex]`. Lazy rebuild from SQLite on first search or when marked dirty. Incremental insert on `saveMemoryEmbedding`. Remove on `deleteMemory`. Tier filter: 3x over-fetch from HNSW, post-filter by tier.
- **Integration:** `DatabaseCodeChunkManager` same pattern but with composite keys (`resourceId:chunkIndex`). N+1 metadata fetch (each result is a PK-indexed lookup — acceptable for N ≤ 20).
- **Thread safety:** Callers serialize via `DatabaseManager.queue` (serial DispatchQueue). No internal locking in `HNSWIndex`.

**Gate:** All tests pass. Manual QA pass. Ready for alpha release. ⬜ (blocked on 5.4, 5.5, and 4.3-4.4)

---

## Open Issues & Known Problems

1. **`IndexStats` struct** in `Services/Index/Models/IndexStats.swift` still has `aiEnrichedResourceCount` and `averageAIQualityScore` fields — always 0 since AIEnrichment was deleted. Cosmetic only. Fix when touching this file.
2. **`DatabaseManager.getAIEnrichedSummaries`, `getAIEnrichedResourceCountScoped`, `getAverageAIQualityScoreScoped`** — always return 0/empty. Legacy API surface.
3. **Pre-existing test target failure** — `EventSource` SPM dependency fails to resolve C-module dependencies (`CAsyncHTTPClient`, `CNIOLLHTTP`, `CNIOPosix`, `CNIOExtrasZlib`, `_NumericsShims`). Not caused by refocus changes.
4. **28 singletons** — Tracked for Phase 5.4. Notable: `InlineAIPopoverManager` uses `.disabled` singleton (introduced in 5.1).
5. **~50+ force unwraps** — Tracked for Phase 5.5. Widespread across entire codebase.
6. **HNSW index not persisted** — Rebuilt from SQLite on first search after startup or data mutation. ~100-500ms rebuild cost for 5000 vectors. Acceptable.
7. **HNSW `rebuildIfNeeded()`** exists but is not called automatically. Lazy deletions accumulate. If active:deleted ratio exceeds 70:30, quality may degrade.

## Build Verification Command

```bash
xcodebuild build -scheme osx-ide 2>&1 | grep -E "\.swift:.*error:"
```

Expected: no Swift compilation errors from our changes. Non-zero exit may be from SPM pre-existing issue (see Open Issues #3).

## Recovery Commands

```bash
# View all refocus commits
git log refocus-v1 --oneline

# View diff summary
git diff main...refocus-v1 --stat

# Checkout and build
git checkout refocus-v1
xcodebuild build -scheme osx-ide
```

## Execution Rules

1. **Every phase ends with a working build.** Run `xcodebuild build -scheme osx-ide` and verify no Swift compilation errors from our changes before marking a phase complete.
2. **No mixing phases.** Complete all items in Phase N before starting Phase N+1.
3. **If a phase reveals unexpected coupling, stop and document it.** Do not "just fix it" — track the coupling and decide if it needs a design change or belongs in a later phase.
4. **Each phase can be shipped independently.** If priorities change, any completed phase delivers standalone value.
