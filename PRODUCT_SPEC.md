# Product Specification

## Target User

**Primary:** Professional macOS developer using a 16GB M4 MacBook Pro (or equivalent Apple Silicon). They work on codebases ranging from small side projects to large production systems. They value speed and privacy over cloud features they don't trust or can't afford.

**Secondary:** Developers who want a single editor for both daily coding and complex agentic work. They use cloud models for the heavy lifting but want instant local AI for the daily flow.

**Non-target:** Users on non-Mac platforms (Windows, Linux), users with <16GB RAM, users who want a purely cloud-based IDE (Cursor, Windsurf, GitHub Codespaces).

## Feature Matrix

### Local Pipeline (4B MLX) — Always On, Always Private

| Feature | Status | Priority | Notes |
|---|---|---|---|
| Inline code completion (ghost text) | ✅ Implemented | P0 | Works. Tune for 4B latency (<100ms). Improve context awareness. |
| Ghost text rendering (Tab accept, Esc dismiss) | ✅ Implemented | P0 | Works. |
| Completion trigger policy (debounce, language check) | ✅ Implemented | P1 | Review for 4B model. |
| Completion context assembly (prefix, suffix, scope) | ✅ Implemented | P1 | Improve with index context. |
| Completion caching | ✅ Implemented | P2 | |
| Completion ranking (filter duplicates, indentation) | ✅ Implemented | P1 | |
| Completion telemetry | ✅ Implemented | P3 | |
| Completion settings UI | ✅ Implemented | P1 | |
| Completion debug overlay | ✅ Implemented | P3 | |

| Inline AI popover (cursor-anchored Q&A) | ❌ Not implemented | P0 | THE key missing feature. Anchored to cursor, scoped to file/selection. |
| Inline popover: explain code | ❌ Not implemented | P0 | "Explain this function" — instant 4B response. |
| Inline popover: quick refactor | ❌ Not implemented | P1 | "Rename variable", "extract method" — simple transforms. |
| Inline popover: fix diagnostics | ❌ Not implemented | P1 | "How do I fix this warning?" — gutter-triggered. |
| Inline popover: find similar code | ❌ Not implemented | P2 | Semantic search for similar patterns. |
| Inline popover: quick docs | ❌ Not implemented | P3 | Show documentation for symbol under cursor. |

| Direct chat with local model | 🟡 Partial | P1 | Exists as "offline mode" in chat panel. Needs dedicated local-only chat UI. |
| Semantic search (vector-based) | 🟡 Partial | P1 | Index has embeddings but O(n) search. Need ANN (HNSW). |
| Diagnostics explanation | ❌ Not implemented | P1 | "Why is this line flagged?" — gutter button → inline popover. |
| Code transform: rename | ❌ Not implemented | P2 | Local model suggests rename + preview. |
| Code transform: extract | ❌ Not implemented | P2 | Local model suggests extraction + preview. |
| Code transform: fix | ❌ Not implemented | P2 | Local model suggests fix for errors. |

### Cloud Pipeline (OpenRouter) — On Demand, Full Power

| Feature | Status | Priority | Notes |
|---|---|---|---|
| Chat with cloud model | ✅ Implemented | P0 | Works via OpenRouter. |
| Orchestration graph (Planner → Worker → QA → Final) | ✅ Implemented | P0 | Exists. Fix bugs, polish execution. |
| Tool loop with stall detection | ✅ Implemented | P0 | Works (2,824 lines). Fix remaining bugs. |
| Tool execution (20+ tools) | ✅ Implemented | P0 | Works. |
| RAG context injection | ✅ Implemented | P1 | Currently hybrid. Make cloud-only. |
| RAG: intent classification | ✅ Implemented | P1 | |
| RAG: evidence fusion ranking | ✅ Implemented | P1 | |
| RAG: code segment retrieval | ✅ Implemented | P1 | |
| RAG: project overview | ✅ Implemented | P1 | |
| RAG: symbol search | ✅ Implemented | P1 | |
| QA review | ✅ Implemented | P2 | Optional quality gate. |
| Plan synthesis | ✅ Implemented | P2 | Strategic + tactical planning. |
| Conversation folding | ✅ Implemented | P2 | Compress long histories. |
| Conversation history persistence | ✅ Implemented | P0 | |
| Streaming responses | ✅ Implemented | P0 | |
| Multi-file refactoring | 🟡 Partial | P0 | Works but reliability varies. |
| Autonomous task execution | 🟡 Partial | P0 | Works but reliability varies. |

### Shared Infrastructure

| Feature | Status | Priority | Notes |
|---|---|---|---|
| CodebaseIndex: file indexing | ✅ Implemented | P0 | |
| CodebaseIndex: FTS5 search | ✅ Implemented | P0 | |
| CodebaseIndex: symbol extraction | ✅ Implemented | P0 | |
| CodebaseIndex: file watching | ✅ Implemented | P0 | |
| CodebaseIndex: embedding-based semantic search | 🟡 Partial | P1 | O(n) scan, needs ANN. |
| CodebaseIndex: memory system | 🟡 Partial | P2 | Overengineered for value. Keep minimal. |
| CodebaseIndex: AI enrichment | 🟡 Partial | P3 | Expensive, unclear value. Re-evaluate. |
| NSTextView editor with syntax highlighting | ✅ Implemented | P0 | |
| Multi-file tree | ✅ Implemented | P0 | |
| Terminal integration | ✅ Implemented | P0 | |
| Command palette | ✅ Implemented | P0 | |
| Keyboard shortcuts | ✅ Implemented | P0 | |
| Layout persistence | ✅ Implemented | P0 | |
| Settings UI | ✅ Implemented | P0 | |
| Accessibility identifiers | ✅ Implemented | P2 | |

## Phased Roadmap

### Phase 0: Assessment & Foundation (Current State)

**What we have:** A working Mac IDE with a solid editor, a good codebase index, a functional inline completion engine, and a working cloud pipeline with orchestration. Also: ~10,000 lines of misaligned code, 28 singletons, a god object ConversationManager, and RAG injected into every request regardless of pipeline.

**Key insight:** We don't need to build from scratch. We need to cut aggressively and refine ruthlessly.

### Phase 1: Refocus (Weeks 1-3)

**Goal:** Eliminate bloat, establish clean pipeline boundaries.

**Delete:**
- `Services/Index/Memory/` (MemoryEmbeddingGenerator, MemoryManager, ProtectionCalculator)
- `Services/Index/Scoring/` (SwiftHeuristicScorer, QualityScoringEngine)
- `Services/Index/AIEnrichment.swift`
- `Components/RAGStatusGauge.swift` (unused)
- `Services/Memory/SearchProviding.swift` (empty file)
- RAG context injection from `AIInteractionCoordinator` (local path)
- Orchestration from local model path (remove the `usesLocalModel` branch in graph)

**Refactor:**
- Split `ConversationManager` into `SessionManager` + `LocalInteractionService` + `CloudConversationService`
- Rename `Services/ConversationFlow/` → `Services/CloudPipeline/`
- Move `Services/InlineCompletion/` → `Services/LocalPipeline/InlineCompletion/`
- Create `AIRouter` (simple if/else for now)

**Outcome:** Clean separation. Local path is ~200 lines of simple code. Cloud path retains full orchestration. All AI services are clearly scoped.

### Phase 2: Local Excellence (Weeks 4-8)

**Goal:** Make the local pipeline genuinely world-class — faster and more useful than any cloud completion engine.

**Inline completion tuning:**
- Measure and optimize latency for 4B MLX model (target: <100ms mean, <200ms p95)
- Improve completion context with CodebaseIndex (symbols, same-file context)
- Pre-warm model for common patterns
- Implement partial acceptance (word-by-word Tab)

**Inline AI popover (new feature):**
- Build cursor-anchored popover component (NSTextView overlay)
- Explain: selected code → 4B model → explanation in popover
- Quick refactor: selected code → "rename/extract/fix" → diff preview → apply
- Diagnostics gutter: click diagnostic → explain in popover
- Keyboard shortcut: Cmd+I for current selection

**Semantic search:**
- Replace O(n) vector scan with HNSW index
- Fall back to FTS5 when HNSW unavailable
- Target: <50ms search across 100K chunks

### Phase 3: Cloud Parity (Weeks 9-16)

**Goal:** Cloud pipeline matches or exceeds Cursor/Windsurf agentic capability.

**Orchestration fixes (from existing bug reports):**
- Fix plan supervision (don't mark incomplete plans as done)
- Fix tool loop stall detection edge cases
- Improve recovery strategies (currently ~10, may have gaps)
- Add comprehensive logging for debugging agent runs

**RAG refinement:**
- Make RAG cloud-only (ARCHITECTURE.md rule)
- Improve retrieval precision (fewer, better results)
- Reduce latency of retrieval pipeline
- Add telemetry to measure RAG impact on output quality

**Tool improvements:**
- Review all 20+ tools for reliability
- Add sandboxing improvements
- Improve file writing with diff-preview-first flow
- Add tool timeout and recovery

**Testing:**
- Improve harness tests for agentic scenarios
- Add regression tests for known bugs
- Measure and track success rate over time

### Phase 4: Experience Engine (Weeks 17-24)

**Goal:** Make the editor learn from user patterns and get smarter over time.

**Pattern tracking:**
- Track co-edited files (user edits files A and B together → suggest them together)
- Track common refactorings (user renames X often → suggest rename earlier)
- Track diagnostic patterns (user always ignores this rule → suppress it)

**Smart defaults:**
- Auto-suggest index-based completions for recently used APIs
- Auto-adjust completion aggressiveness based on user acceptance rate
- Learn which files the user cares about most and prioritize them in retrieval

**Mac integration:**
- Spotlight indexing of project files
- Shortcuts app integration
- AppleScript support
- Service menu entries

## What We Explicitly Do NOT Build

This list is as important as the feature list. These are things that seem tempting but would dilute focus.

| Feature | Reason Excluded |
|---|---|
| Cross-platform support | We compete on Mac integration and Apple Silicon optimization. Electron/Win/Linux support would split focus and compromise performance. |
| Plugin system (v1) | Product needs to be excellent before it needs extensibility. v2 consideration. |
| Built-in issue tracker | Users have GitHub/GitLab/Jira. Build integration, not replacement. |
| Design mode / visual editor | Not an AI IDE feature. Focus on code. |
| Inline AI chat (Cmd+Shift+I) | The spec says this. We're replacing it with the inline popover (Cmd+I). Drop the confusing shortcut collision. |
| Agentic mode for local model | The 4B model cannot do this reliably. It would trash the codebase and we'd get bad reviews. Cloud-only. |
| Memory / long-term storage (v1) | AI-written "memories" of the codebase have unclear value. Let patterns emerge naturally from the Experience Engine instead. |
| AI-generated file summaries | The AIEnrichment feature. It's expensive (calls cloud AI for every file) and summaries are rarely useful. Cut it. |
| Auto-fix-all mode | Too dangerous without user review. Always show diffs first. |
| Model training/fine-tuning | That's a separate product. We consume models, we don't train them. |

## Success Criteria by Phase

### Phase 1 Success
- Local pipeline has zero orchestration code
- Cloud pipeline has zero local-model-specific code
- `ConversationManager` is split into three focused services
- All RAG injection removed from local path
- Project compiles and tests pass

### Phase 2 Success
- Inline completion mean latency <100ms with 4B model
- Inline popover works for explain, quick refactor, diagnostics
- Semantic search returns results in <50ms
- Users report local AI feels "instant"

### Phase 3 Success
- Cloud pipeline agentic success rate >80% on standard coding tasks
- Tool loop stall rate <5%
- RAG retrieval precision >70%
- Harness tests all green

### Phase 4 Success
- Experience engine surfaces relevant suggestions without being asked
- Pattern-based suggestions feel "helpful, not annoying"
- Mac integration features in use by early adopters

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

### Code Quality KPIs
- Singleton count: target <5 (from 28)
- Force unwrap count: target 0 (from ~50+)
- ConversationManager size: target <300 lines (from 981)
- ToolLoopHandler size: target <1500 lines (from 2824)
- Test pass rate: 100%
- Code coverage: target >60%
