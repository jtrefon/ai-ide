# Phase 1 Implementation Plan — Foundation & Coder MVP

> **Duration**: ~20 engineering days (can be parallelized)
> **Scope**: Coder Mode MVP — read, write, search, web search/browse, project structure
> **Out of scope**: Agent mode, DAG scheduling, sub-agents, background jobs, patch tool, terminal tools
> **Principle**: Each week produces a testable, runnable increment. No week-long silos.

---

## Week 1 — Value Types & Registry

**Goal**: All the data types exist, are tested, and tools can be registered.

### Day 1 — Core Value Types

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `ToolCapability` enum | `Services/Tooling/ToolCapability.swift` | 30 | — |
| `ToolSideEffect` enum | `Services/Tooling/ToolSideEffect.swift` | 20 | — |
| `ToolIsolation` enum | `Services/Tooling/ToolIsolation.swift` | 15 | — |
| `ToolFeedbackStatus` enum | `Services/Tooling/ToolFeedback.swift` | 15 | — |
| `ToolFeedback` struct | `Services/Tooling/ToolFeedback.swift` | 60 | ToolFeedbackStatus, ToolErrorInfo |
| `ToolErrorInfo` struct | `Services/Tooling/ToolFeedback.swift` | 30 | — |
| `ToolAlternative` struct | `Services/Tooling/ToolFeedback.swift` | 20 | — |
| `ToolContent` struct | `Services/Tooling/ToolFeedback.swift` | 40 | ToolContentData, ToolContentItem |
| `ToolContentData` enum | `Services/Tooling/ToolFeedback.swift` | 20 | — |
| `ToolContentItem` struct | `Services/Tooling/ToolFeedback.swift` | 20 | — |
| Tests for all types | `osx-ideTests/Tooling/ToolFeedbackTests.swift` | 80 | ToolFeedback |

**Acceptance criteria**: All types are `Sendable` + `Codable`. Unit tests pass. Can construct a `ToolFeedback` with any status/content/error combination.

### Day 2 — ToolDefinition & Related Types

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `JSONSchema` type (replaces raw `[String: Any]`) | `Services/Tooling/JSONSchema.swift` | 40 | — |
| `PromptMaterial` struct | `Services/Tooling/ToolDefinition.swift` | 30 | — |
| `FeedbackDocumentation` struct | `Services/Tooling/ToolDefinition.swift` | 20 | — |
| `ErrorCodeDocumentation` struct | `Services/Tooling/ToolDefinition.swift` | 15 | — |
| `FallbackTool` struct | `Services/Tooling/ToolDefinition.swift` | 15 | — |
| `ToolExecutionRequest` struct | `Services/Tooling/ToolDefinition.swift` | 15 | ExecutionContext |
| `ExecutionContext` struct | `Services/Tooling/ToolDefinition.swift` | 15 | — |
| `ToolDefinition` struct + factory methods | `Services/Tooling/ToolDefinition.swift` | 80 | All of the above |
| `AgentMode` update (add `isAvailableForModel`) | `Services/Tooling/AgentMode.swift` | 20 | — |
| Tests | `osx-ideTests/Tooling/ToolDefinitionTests.swift` | 60 | ToolDefinition |

**Acceptance criteria**: `ToolDefinition.command()` and `.query()` factory methods compile. Tools can be defined with schema, capabilities, side effects, prompt material. Tests verify factory methods produce correct definitions.

### Day 3 — Registry + Tool Call/Result

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `ToolRegistryProtocol` | `Services/Tooling/ToolRegistryProtocol.swift` | 15 | ToolDefinition |
| `ToolRegistry` actor | `Services/Tooling/ToolRegistry.swift` | 60 | ToolRegistryProtocol |
| `ToolCall` struct (decoded model call) | `Services/Tooling/ToolCall.swift` | 60 | — |
| `ToolResult` struct (execution wrapper) | `Services/Tooling/ToolResult.swift` | 40 | ToolFeedback |
| Tests | `osx-ideTests/Tooling/ToolRegistryTests.swift` | 60 | ToolRegistry |

**Acceptance criteria**: Registry registers tools, queries by name and capability, rejects duplicates. ToolCall decodes from JSON. ToolResult wraps ToolFeedback. All tests pass.

### Day 4 — Tool Invocation Context

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `ToolInvocationContext` (v2, replaces old) | `Services/Tooling/Infrastructure/ToolInvocationContext.swift` | 30 | ExecutionContext |
| `ToolFileAccessLedger` (v2, turn-aware) | `Services/Tooling/Infrastructure/ToolFileAccessLedger.swift` | 60 | — |
| `ToolFileExclusion` (move from Core/) | `Services/Tooling/Infrastructure/ToolFileExclusion.swift` | 50 | — |
| Tests for ledger + exclusion | `osx-ideTests/Tooling/ToolFileAccessLedgerTests.swift` | 40 | ToolFileAccessLedger |

**Acceptance criteria**: Ledger tracks reads per turn, enforces read-before-write queries. Exclusion filters vendor dirs correctly.

### Day 5 — Buffer + Integration Test

| Task | Est. Time | Description |
|------|-----------|-------------|
| Review + fix any Week 1 gaps | 2h | Address PR feedback |
| Integration test: register 3 tools, query by capability | 3h | Tests that types actually wire together |
| Update `architecture-v2.md` with any learnings | 1h | Document deviations from plan |

**Week 1 deliverable**: All value types exist, tested, and a script can construct a `ToolRegistry`, register mock tools, query them by capability, and get `ToolFeedback` back. No execution yet — just data flow.

---

## Week 2 — Execution Layer

**Goal**: Tools can be executed through the decorator chain. Sandbox, governance, and scheduling work.

### Day 1 — ToolExecutor Protocol + RealToolExecutor

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `ToolExecutor` protocol | `Services/Tooling/Execution/ToolExecutor.swift` | 10 | ToolExecutionRequest |
| `RealToolExecutor` | `Services/Tooling/Execution/RealToolExecutor.swift` | 80 | ToolExecutor, ToolRegistry |
| Tests: executor finds tool, calls execute, returns feedback | `osx-ideTests/Tooling/RealToolExecutorTests.swift` | 60 | RealToolExecutor |

**Acceptance criteria**: Executor takes a ToolCall, looks up definition in Registry, calls the execute closure, returns ToolFeedback. Works with mock tools.

### Day 2 — SandboxDecorator

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `SandboxConfiguration` struct | `Services/Tooling/Infrastructure/SandboxConfiguration.swift` | 30 | — |
| `PathValidator` (v2, move from Services/) | `Services/Tooling/Infrastructure/PathValidator.swift` | 80 | — |
| `SandboxDecorator` | `Services/Tooling/Execution/SandboxDecorator.swift` | 100 | ToolExecutor, PathValidator, ToolFileAccessLedger |
| Tests: read-before-write enforcement, path blocking | `osx-ideTests/Tooling/SandboxDecoratorTests.swift` | 80 | SandboxDecorator |

**Acceptance criteria**: Decorator blocks writes without prior read (returns `MUTATION_WITHOUT_PRIOR_READ`). Allows new file creation. Allows reads. Error includes alternatives. Coder mode only — Agent mode skips check.

### Day 3 — WorkerPool + ResourceGovernor

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `WorkerPool` actor | `Services/Tooling/Execution/WorkerPool.swift` | 120 | ToolExecutor |
| `ResourceGovernor` actor | `Services/Tooling/Execution/ResourceGovernor.swift` | 150 | WorkerPool |
| `MainActorWorker` | `Services/Tooling/Execution/MainActorWorker.swift` | 60 | ToolExecutor |
| Tests: concurrent execution, timeout, memory cap | `osx-ideTests/Tooling/WorkerPoolTests.swift` | 100 | WorkerPool |

**Acceptance criteria**: Pool runs N concurrent tools (configurable). Timeout kills long-running tools. MainActorWorker routes web tools to main thread. Memory tracking works.

### Day 4 — SequentialScheduler + ToolLoopGuard

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| Move `ToolScheduler` + `AsyncSemaphore` to `Tooling/Scheduling/` | Files moved, no new code | — | — |
| `SequentialScheduler` actor | `Services/Tooling/Scheduling/SequentialScheduler.swift` | 40 | ResourceGovernor |
| `ToolLoopGuard` actor (extract from ToolLoopHandler) | `Services/Tooling/Guard/ToolLoopGuard.swift` | 100 | — |
| Tests: scheduler execution order, loop guard repetition | `osx-ideTests/Tooling/SequentialSchedulerTests.swift` | 60 | SequentialScheduler |

**Acceptance criteria**: SequentialScheduler runs tools one at a time. ToolLoopGuard detects 3× repeated same call. Both integrate with ResourceGovernor.

### Day 5 — Full Decorator Chain Integration Test

| Task | Est. Time | Description |
|------|-----------|-------------|
| Wire decorator chain: TelemetryDecorator → SandboxDecorator → RealToolExecutor | 2h | Build the chain |
| Test: full chain with mock read/write tools | 3h | Test sandbox blocks, telemetry records, executor runs |
| Test: MainActorWorker dispatches web tools correctly | 1h | Verify routing |
| Update architecture doc with any changes | 1h | Document deviations |

**Week 2 deliverable**: A tool call can flow through the full chain: scheduler → governance → sandbox → executor → feedback. Sandbox blocks bad calls. Timeout kills slow calls. All return structured ToolFeedback.

---

## Week 3 — Tool Porting + Orchestration

**Goal**: 16 tools are ported to the new architecture. The CoderOrchestrator can handle a user request end-to-end.

### Day 1 — Port Tier 1: Search + File Listing

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| Wrap `search_project` → ToolDefinition | `Services/Tools/SearchProjectTool+v2.swift` | 30 | ToolDefinition, ToolFeedback |
| Wrap `list_files` → ToolDefinition | `Services/Tools/ListFilesTool+v2.swift` | 20 | ToolDefinition, ToolFeedback |
| Wrap `find_file` → ToolDefinition | `Services/Tools/FindFileTool+v2.swift` | 20 | ToolDefinition, ToolFeedback |
| Wrap `get_project_structure` → ToolDefinition | `Services/Tools/GetProjectStructureTool+v2.swift` | 20 | ToolDefinition, ToolFeedback |
| Register all 4 in `ToolRegistrar` | `Services/Tooling/Registry/ToolRegistrar.swift` | 20 | ToolRegistry |

**Acceptance criteria**: 4 tools wrapped and registered. Each produces `ToolFeedback` (not raw String). Tests verify output format.

### Day 2 — Port Tier 2: Index Tools + Web Tools

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| Wrap 6 index tools → ToolDefinition | `Services/Tools/IndexToolWrappers.swift` | 6×20 = 120 | ToolDefinition, ToolFeedback |
| Wrap `web_search` → ToolDefinition | `Services/Tools/WebSearchTool+v2.swift` | 20 | ToolDefinition, ToolFeedback |
| Wrap `web_browse` → ToolDefinition | `Services/Tools/WebBrowseTool+v2.swift` | 20 | ToolDefinition, ToolFeedback |
| Wrap `web_session_store` (internal) | Already internal, no wrapper needed | 0 | — |
| Register all 8 in `ToolRegistrar` | Update `ToolRegistrar.swift` | 10 | ToolRegistry |

**Acceptance criteria**: All 12 (4+8) tools ported. Web tools route through MainActorWorker. Index tools route through background workers.

### Day 3 — FilePathIndex (Trie)

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `FilePathIndex` actor with trie | `Services/Tooling/Index/FilePathIndex.swift` | 120 | — |
| `FileWalker` async sequence | `Services/Tooling/Index/FileWalker.swift` | 40 | — |
| Integration with `search_project` (replace FileManager grep) | Update SearchProjectTool wrapper | 30 | FilePathIndex |
| Tests: trie build, search, FSEvents update | `osx-ideTests/Tooling/FilePathIndexTests.swift` | 80 | FilePathIndex |

**Acceptance criteria**: Trie builds in ~100ms for 10K files. Prefix search in ~0.1ms. Substring search in ~1ms. FSEvents hook ready. search_project uses trie for filename tier.

### Day 4 — CoderOrchestrator

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `CoderOrchestrator` | `Services/Tooling/Orchestration/CoderOrchestrator.swift` | 120 | ToolRegistry, ToolExecutor, SequentialScheduler, ToolFormatAdapter |
| `ToolFormatAdapter` protocol | `Services/Tooling/Adapters/ToolFormatAdapter.swift` | 20 | ToolDefinition, ToolCall |
| `OpenRouterToolAdapter` | `Services/Tooling/Adapters/OpenRouterToolAdapter.swift` | 100 | ToolFormatAdapter |
| `ToolFeedbackFormatter` | `Services/Tooling/Feedback/ToolFeedbackFormatter.swift` | 80 | ToolFeedback |
| Tests: orchestrator flow with mock AI | `osx-ideTests/Tooling/CoderOrchestratorTests.swift` | 80 | CoderOrchestrator |

**Acceptance criteria**: Orchestrator takes a SendRequest, queries registry for Coder-mode tools, encodes them via adapter, calls mock AI, gets tool calls back, executes them via decorator chain, encodes feedback, returns response. Full flow works with mocks.

### Day 5 — Integration Test: End-to-End

| Task | Est. Time | Description |
|------|-----------|-------------|
| Build end-to-end test: "find NetworkManager and read it" | 3h | Full flow with real registry + mock AI |
| Test with sandbox: try write without read → verify block | 1h | Sandbox integration |
| Test with governance: run 5 tools → verify max 4 concurrent | 1h | WorkerPool integration |
| Test web tools route to MainActorWorker | 1h | Verify routing |
| Fix any integration issues | 2h | — |

**Week 3 deliverable**: End-to-end Coder mode works. User sends "find NetworkManager and add error handling", orchestrator: gets tools from registry → calls AI → gets tool calls → sandbox checks → executes → returns feedback → AI responds. All with mocks.

---

## Week 4 — Core Rewrites + DI Integration

**Goal**: Real tools (not mocks) work. The new system integrates with the existing app.

### Day 1-2 — Rewrite read_file

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `ReadFileTool` rewrite (Data-based, line-range) | `Services/Tools/ReadFileTool+v2.swift` | 120 | ToolDefinition, PathValidator, ResourceGovernor |
| Tests: full file read, line range, mmap, binary detection | `osx-ideTests/Tools/ReadFileToolTests.swift` | 100 | ReadFileTool |

**Acceptance criteria**: 
- Small file (<1MB): `Data(contentsOf:)` + line scanning
- Line range: `Data.split(separator: 0x0A)` + byte range extraction
- Large file (>1MB): mmap-based, zero-copy for unmodified parts
- Binary file detection: return "<binary file>" instead of loading
- All I/O goes through `ResourceGovernor.readIO()`
- Swarm: 100 concurrent line-range reads = ~1ms total CPU

### Day 2-3 — Rewrite write_file + tool_file_access_ledger

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| `WriteFileTool` rewrite (no propose mode, add read-before-write) | `Services/Tools/WriteFileTool+v2.swift` | 80 | ToolDefinition, PathValidator, ToolFileAccessLedger |
| Merge `FileToolWriteApplier` into WriteFileTool | Merge into above | 30 | — |
| `ToolFileAccessLedger` v2 (turn-aware) | Already done in Week 1 | 0 | — |
| Tests: write new file, write existing (blocked), write after read (allowed) | `osx-ideTests/Tools/WriteFileToolTests.swift` | 80 | WriteFileTool |

**Acceptance criteria**:
- Write new file: succeeds (no read required)
- Write existing file without prior read: blocked with `MUTATION_WITHOUT_PRIOR_READ`
- Write existing file after read: succeeds
- Write goes through `ResourceGovernor.writeIO()` (per-file lock)
- Output is `ToolFeedback`, not raw String
- Propose mode removed (not needed for Coder)
- FileToolWriteApplier merged (no separate file)

### Day 3 — DependencyContainer Integration

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| Delete old files: `file_tool_proposal_stager`, `file_tool_param_schema`, `tool_invocation_context` | Delete | — | — |
| Update `AIMode.swift` with `isAvailableForModel` | `Services/Models/AIMode.swift` | 10 | — |
| Add `makeToolingStack()` to `DependencyContainer` | `Services/DependencyContainer.swift` | 60 | All Tooling types |
| Move `ToolScheduler` + `AsyncSemaphore` aliases | Keep old location, add new | 10 | — |

**Acceptance criteria**: DependencyContainer creates the full tooling stack. Old types still work (coexistence). New stack is accessible.

### Day 4 — ConversationManager Integration

| Task | File | Est. Lines | Depends On |
|------|------|-----------|------------|
| Add `useNewArchitecture` flag to `ConversationManager` | `Services/ConversationManager.swift` | 20 | CoderOrchestrator |
| Route Coder mode requests to CoderOrchestrator | `Services/ConversationManager.swift` | 30 | CoderOrchestrator |
| Route Chat mode requests to existing flow (no change) | No change | 0 | — |
| LegacyToolAdapter for any unported old AITool | `Services/Tooling/Execution/LegacyToolAdapter.swift` | 30 | ToolDefinition, AITool |

**Acceptance criteria**: When `useNewArchitecture = true`, Coder mode requests go through CoderOrchestrator. Chat mode unchanged. Old Agent mode unchanged. Fallback adapter wraps old tools.

### Day 5 — Integration Tests + Bug Fixes

| Task | Est. Time | Description |
|------|-----------|-------------|
| Full E2E test: real read_file + write_file through orchestrator | 2h | Test with actual file system |
| Test: sandbox blocks write without read on real files | 1h | Verify against real files |
| Test: web search through MainActorWorker | 1h | Real web search |
| Test: 4 concurrent reads, 1 write blocked | 1h | WorkerPool + governance |
| Test: crash recovery (git status check) | 1h | Verify git integration |
| Fix any bugs found | 2h | — |

**Week 4 deliverable**: The full Phase 1 system works. User opens the app in Coder mode, types "find NetworkManager and add error handling", and the system successfully searches, reads, and writes files using real tools. Web search and browse work for documentation lookups.

---

## Phase 1 Complete — Definition of Done

### Functional Requirements

- [ ] User can ask "find X in the project" → `search_project` returns results as `ToolFeedback`
- [ ] User can ask "read file X" → `read_file` returns content with line numbers
- [ ] User can ask "write to file X" → `write_file` creates/updates file
- [ ] User can ask "list files in directory X" → `list_files` returns listing
- [ ] User can ask "find file named X" → `find_file` matches filename
- [ ] User can ask "show project structure" → `get_project_structure` returns tree
- [ ] User can ask "search the web for X" → `web_search` returns results
- [ ] User can ask "open URL X" → `web_browse` returns page text
- [ ] All 6 index tools work: search_text, search_symbols, find_files, list_files, read_file, list_memories, add_memory
- [ ] Read-before-write enforced: write to unknown file → blocked
- [ ] Read-before-write allows: read file → write file → succeeds
- [ ] New file creation: no read required

### Architecture Requirements

- [ ] All tools return `ToolFeedback` (not raw String)
- [ ] All tools are registered in `ToolRegistry`
- [ ] All tools have `ToolDefinition` with capabilities, side effects, prompt material
- [ ] `ToolFormatAdapter.encodeTools()` produces valid OpenAI-compatible JSON schema
- [ ] `ToolFormatAdapter.decodeToolCalls()` parses model tool calls
- [ ] `ToolFormatAdapter.encodeFeedback()` produces model-friendly strings
- [ ] `SandboxDecorator` enforces read-before-write in Coder mode
- [ ] `WorkerPool` limits concurrent tools (4 for Coder)
- [ ] `ResourceGovernor` tracks memory, I/O, network usage
- [ ] `MainActorWorker` routes web tools to main thread
- [ ] `SequentialScheduler` runs one tool at a time (Coder mode)
- [ ] `CoderOrchestrator` handles single-turn request → tools → response
- [ ] `FilePathIndex` provides sub-millisecond filename search
- [ ] `ToolLoopGuard` detects 3× repeated calls
- [ ] `ToolFileAccessLedger` tracks reads per turn

### Testing Requirements

- [ ] Unit tests for all value types: ToolDefinition, ToolFeedback, ToolCall, ToolRegistry
- [ ] Unit tests for ToolExecutor chain: SandboxDecorator, RealToolExecutor
- [ ] Unit tests for WorkerPool + ResourceGovernor: concurrency, timeout, memory
- [ ] Unit tests for CoderOrchestrator: end-to-end with mock AI
- [ ] Unit tests for FilePathIndex: trie build, search, edge cases
- [ ] Unit tests for all 16 ported tools: correct feedback format
- [ ] Unit tests for rewritten tools: read_file line range, write_file read-before-write
- [ ] Integration test: full flow with real filesystem
- [ ] Integration test: sandbox enforcement with real files
- [ ] Integration test: web tools through MainActorWorker

### Migration Requirements

- [ ] Old architecture unchanged (no deletions yet)
- [ ] Old `AITool` protocol still works for Agent mode
- [ ] Old `ConversationToolProvider` still works for Agent mode
- [ ] Old `AIToolExecutor` still works for Agent mode
- [ ] `useNewArchitecture` flag controls which path Coder uses
- [ ] All old tests still pass

---

## Appendix: Complete File Manifest

### New Files (28 files, ~1,970 lines)

```
Services/Tooling/
├── ToolDefinition.swift            # 80 lines
├── ToolCapability.swift            # 30 lines
├── ToolSideEffect.swift            # 20 lines
├── ToolIsolation.swift             # 15 lines
├── ToolFeedback.swift              # 200 lines (all feedback types)
├── ToolCall.swift                  # 60 lines
├── ToolResult.swift                # 40 lines
├── JSONSchema.swift                # 40 lines
├── AgentMode.swift                 # 20 lines
├── Registry/
│   ├── ToolRegistry.swift          # 60 lines
│   ├── ToolRegistryProtocol.swift  # 15 lines
│   └── ToolRegistrar.swift         # 30 lines
├── Execution/
│   ├── ToolExecutor.swift          # 10 lines
│   ├── RealToolExecutor.swift      # 80 lines
│   ├── SandboxDecorator.swift      # 100 lines
│   ├── TelemetryDecorator.swift    # 50 lines
│   ├── WorkerPool.swift            # 120 lines
│   ├── ResourceGovernor.swift      # 150 lines
│   ├── MainActorWorker.swift       # 60 lines
│   └── LegacyToolAdapter.swift     # 30 lines
├── Scheduling/
│   ├── SequentialScheduler.swift   # 40 lines
│   ├── ToolScheduler.swift         # moved, no new code
│   └── AsyncSemaphore.swift        # moved, no new code
├── Feedback/
│   └── ToolFeedbackFormatter.swift # 80 lines
├── Orchestration/
│   └── CoderOrchestrator.swift     # 120 lines
├── Guard/
│   └── ToolLoopGuard.swift         # 100 lines
├── Index/
│   ├── FilePathIndex.swift         # 120 lines
│   └── FileWalker.swift            # 40 lines
├── Infrastructure/
│   ├── ToolFileAccessLedger.swift  # 60 lines
│   ├── ToolInvocationContext.swift # 30 lines
│   ├── ToolFileExclusion.swift     # 50 lines
│   ├── PathValidator.swift         # 80 lines
│   └── SandboxConfiguration.swift  # 30 lines
└── Adapters/
    ├── ToolFormatAdapter.swift     # 20 lines
    └── OpenRouterToolAdapter.swift # 100 lines
```

### Modified Files (4 files)

```
Services/DependencyContainer.swift    # +60 lines (makeToolingStack)
Services/ConversationManager.swift    # +50 lines (useNewArchitecture flag)
Services/Models/AIMode.swift          # +20 lines (isAvailableForModel)
```

### Deleted Files (4 files, after cutover)

```
Services/Tools/FileToolProposalStager.swift
Services/Tools/FileToolParameterSchemaBuilder.swift
Services/Tools/ToolInvocationContext.swift
Services/Tools/LocalFindTool.swift          # deprecated
```

### Test Files (14 files, ~940 lines)

```
osx-ideTests/Tooling/
├── ToolFeedbackTests.swift           # 80 lines
├── ToolDefinitionTests.swift         # 60 lines
├── ToolRegistryTests.swift           # 60 lines
├── ToolFileAccessLedgerTests.swift   # 40 lines
├── RealToolExecutorTests.swift       # 60 lines
├── SandboxDecoratorTests.swift       # 80 lines
├── WorkerPoolTests.swift             # 100 lines
├── SequentialSchedulerTests.swift    # 60 lines
├── FilePathIndexTests.swift          # 80 lines
├── CoderOrchestratorTests.swift      # 80 lines
├── ReadFileToolTests.swift           # 100 lines
├── WriteFileToolTests.swift          # 80 lines
├── Integration/
│   ├── EndToEndFlowTests.swift       # 60 lines
│   └── SandboxIntegrationTests.swift # 40 lines
```
