# Refocus Tracker

## Phase 0 — Foundation ✅ (Completed)

**Theme:** Vision, cuts, and cleanup.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 0.1 | Write VISION.md, ARCHITECTURE.md, PRODUCT_SPEC.md | 🔑 Sets direction | — | ✅ |
| 0.2 | Delete Scoring/ directory | 🗑️ Removes unreachable code | — | ✅ |
| 0.3 | Delete AIEnrichment + related events + DB manager | 🗑️ Removes unreachable code | 0.2 | ✅ |
| 0.4 | Delete RAGStatusGauge (unused UI) | 🗑️ Removes dead code | — | ✅ |
| 0.5 | Remove AIEnrichment from CodebaseIndexProtocol + all callers | 🏗️ Cleans protocol surface | 0.3 | ✅ |
| 0.6 | Fix all test mocks + DB stubs | ✅ Maintains green build | 0.5 | ✅ |

**Gate:** Build must compile (no Swift errors from our changes). ✅

---

## Phase 1 — Pipeline Isolation ✅ (Completed)

**Theme:** Stop blending local and cloud. RAG and orchestration become cloud-only.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 1.1 | Remove RAG injection from local model path in AIInteractionCoordinator | 🔥 **Highest impact** — prevents 4B model from being polluted with irrelevant context | 0.5 | ✅ |
| 1.2 | Remove orchestration graph from local model path (skip nodes, direct LLM call) | 🔥 **Highest impact** — prevents 4B model from running planner/worker/QA nodes | 1.1 | ✅ |
| 1.3 | Update SendRequest/ConversationSendCoordinator to support pipeline routing | 🏗️ Infrastructure for 1.1 + 1.2 | 1.2 | ✅ |

**Gate:** Build must compile. Local model makes direct LLM calls only. Cloud model retains full orchestration + RAG. ✅

---

## Phase 2 — Structural Reorg (Partial)

**Theme:** Directory structure reflects the architecture. Mechanical but important.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 2.1 | Rename `Services/ConversationFlow/` → `Services/CloudPipeline/` | 🏗️ Architecture clarity | 1.2 | ⬜ |
| 2.2 | Move `Services/InlineCompletion/` → `Services/LocalPipeline/InlineCompletion/` | 🏗️ Architecture clarity | — | ⬜ |
| 2.3 | Create `Services/LocalPipeline/LocalInteractionService.swift` | 📦 Scaffold for local-only AI interaction | 1.2 | ✅ |
| 2.4 | Fix all imports and Xcode project references | ✅ Maintains build | 2.1, 2.2, 2.3 | ⬜ |

**Gate:** Build must compile. Directory structure matches ARCHITECTURE.md diagram. (File moves postponed — require Xcode project updates.)

---

## Phase 3 — Architecture Completion (Partial)

**Theme:** Cleanly separate concerns. The router dispatches, two backends serve.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 3.1 | Split `ConversationManager` into `SessionManager` + `CloudConversationService` | 🔥 **Major** — removes god object (981→~300 lines) | 2.1, 2.2 | ⬜ |
| 3.2 | Create `AIRouter` to dispatch requests to local or cloud pipeline | 🏗️ Clean entry point for AI interactions | 3.1 | ⬜ |
| 3.3 | Remove `RAGTelemetryAggregator` (dead code, file + test) | 🗑️ Cleanup | 0.5 | ✅ |

**Gate:** Build must compile.

---

## Phase 4 — Model Optimization

**Theme:** Lock in on Qwen3.6 4B 4bit. Thin adapter, deep optimization.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 4.1 | Create thin `LocalModelAdapter` protocol (50 lines: tokenize, formatPrompt, contextLength) | 🏗️ Enables model swap without abstraction layer bloat | 2.3 | ⬜ |
| 4.2 | Implement `Qwen36Adapter` conforming to `LocalModelAdapter` | 🎯 **High** — optimizes for target model | 4.1 | ⬜ |
| 4.3 | Run coding-specific benchmarks (completion latency, Q&A quality, semantic search) vs current | 📊 Evidence for model lock-in decision | 4.2 | ⬜ |
| 4.4 | Tune inline completion for <100ms p50 with Qwen3.6 | 🎯 **High** — core competitive advantage | 4.3 | ⬜ |

**Gate:** Build must compile. Inline completion achieves <100ms p50 with Qwen3.6 4B 4bit.

---

## Phase 5 — Polish & Ship

**Theme:** Fix the visible features users actually see.

| # | Item | Impact | Depends On | Status |
|---|---|---|---|---|
| 5.1 | Inline AI popover (cursor-anchored Q&A) | 🎯 **High** — biggest missing feature | 3.2 | ⬜ |
| 5.2 | Fix cloud pipeline orchestration bugs (plan supervision, tool loop edge cases) | 🎯 **High** — competing with Cursor | 3.1 | ⬜ |
| 5.3 | Improve semantic search with approximate ANN (HNSW) | 🎯 **Medium** — faster search | 2.1 | ⬜ |
| 5.4 | Remove remaining 28 singletons (migrate to DI container) | 🏗️ Code quality | 3.2 | ⬜ |
| 5.5 | Remove force unwraps (~50+ across codebase) | 🏗️ Crash safety | — | ⬜ |

**Gate:** All tests pass. Manual QA pass. Ready for alpha release.

---

## Execution Rules

1. **Every phase ends with a working build.** Run `xcodebuild build -scheme osx-ide` and verify no Swift compilation errors from our changes before marking a phase complete.
2. **No mixing phases.** Complete all items in Phase N before starting Phase N+1.
3. **If a phase reveals unexpected coupling, stop and document it.** Do not "just fix it" — track the coupling and decide if it needs a design change or belongs in a later phase.
4. **Each phase can be shipped independently.** If priorities change, any completed phase delivers standalone value.
