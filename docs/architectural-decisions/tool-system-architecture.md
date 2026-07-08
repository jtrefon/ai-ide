# Tool System Architecture — Target Design

## Current State Summary

The v1 tool pipeline (`AITool` → `AIToolExecutor` → `ToolLoopHandler`) is battle-tested but has: fragmented argument parsing, duplicated alias tables, a 2,849-line god loop, ad-hoc concurrency, and raw `[String: Any]` throughout. The v2 stack (`ToolDefinition` → `CoderOrchestrator`) has cleaner types but is **dead code** — registered with `nil` dependencies, 10 of 16 tools throw `"not yet implemented"`.

## Design Principles

1. **One type system**: v2's `ToolDefinition`, `ToolValue`, `ToolFeedback`, `JSONSchema`, `ToolCapability`, `ToolSideEffect` become canonical. v1's `AITool` protocol and `[String: Any]` arguments are deleted.
2. **Keep the proven execution path**: `ToolLoopHandler`'s loop logic, stall detection, and recovery strategies are preserved — but extracted into focused components.
3. **Event-driven streaming**: No polling. AsyncSequences and Channels for tool output, progress, and logging.
4. **Plugin tool architecture**: Tools are registered via a protocol, not compiled into a factory. New tools snap in without touching the execution engine.
5. **Single argument parser**: No more duplicated `_raw_args_chunk` regex in 4 places.
6. **Capability-based security**: Every tool declares capabilities. Sandbox enforcement is at the executor level, not in each tool.
7. **Sub-agent ready**: The scheduler supports parallel execution across multiple agents, not just sequential batch.

---

## Layer 1: Tool Model (Types)

Replace both `AITool` (25 lines) and `ToolDefinition` (154 lines) with a unified model:

```swift
/// A tool that can be executed by the system.
/// This replaces both AITool (v1) and ToolDefinition (v2).
protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var schema: JSONSchema { get }
    var capabilities: ToolCapabilities { get }
    var sideEffects: ToolSideEffect { get }
    var isolation: ToolIsolation { get }
    var timeout: TimeInterval { get }

    func execute(_ request: ToolExecutionRequest) async throws -> ToolFeedback
}
```

Supporting types (all from v2, made canonical):

| Type | Role |
|------|------|
| `ToolValue` | Typed argument (`.string`, `.integer`, `.number`, `.boolean`, `.array`, `.dictionary`) — replaces `[String: Any]` |
| `ToolFeedback` | Structured result (`.success`, `.error`, `.partial`) with `ToolContent` + `ToolErrorInfo` |
| `ToolExecutionRequest` | `toolName`, `arguments: [String: ToolValue]`, `context: ExecutionContext` |
| `ToolCapabilities` | OptionSet: `fileRead`, `fileWrite`, `fileDelete`, `fileSearch`, `directoryList`, `indexSearch`, `webSearch`, `webBrowse`, `commandExecution`, `projectStructure` |
| `ToolSideEffect` | OptionSet: `readsFile`, `writesFile`, `deletesFile`, `modifiesFile`, `executesCommand`, `makesNetworkRequest` |
| `ToolIsolation` | `.concurrent`, `.pathIsolated`, `.sessionIsolated`, `.globallySerial` |
| `JSONSchema` | Recursive: `.object(properties, required)`, `.array(items)`, `.string`, `.integer`, `.number`, `.boolean`, `.any` |
| `ExecutionContext` | `conversationId`, `turnId`, `projectRoot`, `mode`, `allowedCapabilities`, `sandbox` |

All tools in `Services/Tools/` get a thin wrapper that converts them to the new `Tool` protocol. The `Tool` protocol wraps the existing v1 implementations — no need to rewrite tool logic.

---

## Layer 2: Tool Registry (Single Source of Truth)

Replaces both `ConversationToolProvider` (ad-hoc array) and `ToolRegistry` (dead code):

```swift
actor ToolRegistry {
    func register(_ tool: any Tool, for modes: Set<AgentMode>)
    func tool(named: String) -> (any Tool)?
    func tools(for mode: AgentMode) -> [any Tool]
    func tools(capability: ToolCapabilities) -> [any Tool]
}
```

**Key properties**:
- Single alias registry: `register(alias: String, for: String)` — `"list_dir"` → `"list_files"`
- Single argument parser (see Layer 3)
- Capability-based queries: `tools(capability: .fileRead)` returns all read-capable tools
- Thread-safe actor (not `NSLock`)

---

## Layer 3: Argument Pipeline (Single Path)

The current _raw_args_chunk_fragmentation across 4 files is consolidated:

```
Tool Call (from AI response)
  │
  ▼
ArgumentCollector (actor)
  │  Receives streaming chunks, buffers, reassembles JSON
  │  No _raw_args_chunk fallback — proper JSON streaming parse
  │  Emits complete ToolValue dictionary
  │
  ▼
ArgumentValidator
  │  Validates against JSONSchema
  │  Applies path normalization (single alias table)
  │  Injects default values
  │
  ▼
ToolExecutionRequest
```

The `ArgumentCollector` replaces `ChunkCollector.parseToolArguments` (in `OpenAICompatibleChatService`), `AIToolCall.decodeArguments()`, `ToolArgumentResolver.normalizeArguments()`, and `Tooling/ToolCall.swift` argument parsing.

---

## Layer 4: Execution Pipeline (Event-Driven)

Replaces `AIToolExecutor` + `ToolScheduler` + watchdog polling:

```
                  ┌──────────────────┐
                  │  ToolScheduler   │ (actor)
                  │                  │
                  │  • Channel-based  │
                  │  • Backpressure   │
                  │  • Path isolation │
                  │  • Multi-agent    │
                  └────────┬─────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ Sandbox  │ │ Sandbox  │ │ Sandbox  │
        │ Decorator│ │ Decorator│ │ Decorator│
        └────┬─────┘ └────┬─────┘ └────┬─────┘
             ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │ RealTool │ │ RealTool │ │ RealTool │
        │ Executor │ │ Executor │ │ Executor │
        └──────────┘ └──────────┘ └──────────┘

Events (via AsyncChannel, not polling):
  ──→ ToolStarted(toolCallId, toolName, targetPath)
  ──→ ToolProgress(toolCallId, chunk)
  ──→ ToolCompleted(toolCallId, result)
  ──→ ToolFailed(toolCallId, error, recoverable)
```

### Concurrency Model

| Isolation | Semantics | Max Concurrent |
|-----------|-----------|----------------|
| `.concurrent` | No restrictions | Unlimited |
| `.pathIsolated` | Serialized per file path | 1 per path |
| `.sessionIsolated` | Serialized per session (e.g., terminal, web) | 1 per session |
| `.globallySerial` | Only one at a time globally | 1 total |

### Watchdog

Replaces polling with a timeout actor:

```swift
actor ToolWatchdog {
    struct WatchEntry {
        let toolCallId: String
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private var entries: [String: WatchEntry] = [:]
    private var timerTask: Task<Void, Never>?

    func watch(toolCallId: String, timeout: TimeInterval) async throws {
        // Register and suspend. The timer task fires on deadline.
        // No polling. No Timer.publish on MainActor.
    }

    func cancel(toolCallId: String)
    func extend(toolCallId: String, by: TimeInterval)
}
```

### Logging Pipeline (Buffered)

Replaces 5 synchronous log destinations with a single buffered log bus:

```
ToolEvent
  │
  ▼
LogBus (actor)
  │  Buffers events (configurable: 100ms or 100 events)
  │  Batch writes to 5 destinations
  │  No Task{} fire-and-forget per event
  │
  ├──→ AppLogger (batched)
  ├──→ EventBus (batched ToolResultEvent)
  ├──→ ExecutionLogStore (batch NDJSON append)
  ├──→ ConversationLogStore (batch NDJSON append)
  └──→ AIToolTraceLogger (batch NDJSON append)
```

---

## Layer 5: Tool Loop (Extracted Concerns)

The 2,849-line `ToolLoopHandler` is split into focused components:

```
ToolLoopOrchestrator (thin coordinator, ~200 lines)
  │
  ├── ToolLoopDriver (the main while loop, extracted)
  │     Only iteration logic + break conditions (~150 lines)
  │
  ├── StallDetector
  │     • RepeatedBatchDetector
  │     • ReadOnlyLoopDetector
  │     • RepeatedWriteTargetDetector
  │     • EmptyResponseDetector
  │     • RepeatedSignatureDetector
  │     • NonRecoverableMutationDetector
  │     (~50 lines each)
  │
  ├── RecoveryStrategy
  │     • DiversifiedExecutionStrategy
  │     • MutationRecoveryStrategy
  │     • ReadOnlyRecoveryStrategy
  │     • StalledFinalizationStrategy
  │     • PlanContinuationStrategy
  │     (~50 lines each)
  │
  ├── ArtifactTracker
  │     • tracks mutation paths
  │     • tracks completed/failed tool signatures
  │     • tracks verification reads
  │     (~100 lines)
  │
  ├── PlanProgressTracker
  │     • advances plan items on mutation
  │     • handles NEEDS_WORK recovery
  │     (~80 lines)
  │
  └── ToolSetProvider
        • mutations tools by mode
        • recovery tool narrowing
        • content write recovery subsets
        (~60 lines)
```

Each component is a separate file, testable in isolation.

---

## Layer 6: Sub-Agent Execution (Future-Proof)

The scheduler supports multiple simultaneous agents:

```swift
actor ToolScheduler {
    private var agents: [AgentID: AgentContext] = [:]

    func registerAgent(_ id: AgentID, capabilities: ToolCapabilities)
    func submit(_ request: ToolExecutionRequest, for agent: AgentID) -> AsyncStream<ToolEvent>

    // AgentA submits write_file, AgentB submits read_file on different paths
    // → Both execute concurrently
    // → Same path → serialized via pathIsolated
}
```

The `ToolIsolation` model (`pathIsolated`, `sessionIsolated`, `globallySerial`, `concurrent`) was designed for this — it maps directly to sub-agents working on different files in parallel.

---

## Layer 7: Security (Capability-Based)

```swift
actor Sandbox {
    struct Policy {
        let allowedCapabilities: ToolCapabilities
        let blockedPathPatterns: [String]
        let requireReadBeforeWrite: Bool
        let allowList: [String]?  // explicit allowed paths
    }

    func authorize(_ request: ToolExecutionRequest, policy: Policy) throws
    // Throws SandboxViolation if capability not allowed or path is blocked
}
```

Each agent/mode has a `Policy`. The `Sandbox` is a single actor — not per-tool logic scattered across `PathValidator`, `SandboxDecorator`, `FileToolWriteApplier`, and `PreWritePreventionEngine`.

---

## Migration Path

| Phase | What | Files Affected |
|-------|------|---------------|
| 1 | Create unified `Tool` protocol + `ToolValue`, `ToolFeedback`, `JSONSchema` as canonical (move from v2 to core) | New files |
| 2 | Create `ToolAliasRegistry` — single alias table, remove duplicates from 3 files | New + delete from `AIToolExecutor+Execution`, `ToolLoopHandler`, `ToolCallFallbackParser` |
| 3 | Create `ArgumentCollector` actor — unified argument parsing, replace `_raw_args_chunk` in 4 locations | New + modify `OpenAICompatibleChatService`, `AIToolCall`, `ToolArgumentResolver`, `Tooling/ToolCall` |
| 4 | Create `ToolWatchdog` — continuous clock-based, remove polling loop | New + delete from `AIToolExecutor+Execution` |
| 5 | Create `ToolScheduler` actor with `ToolIsolation` concurrency model | New + replace `ToolScheduler` (old), `AIToolExecutor+Batch` |
| 6 | Create `LogBus` actor — buffered batch logging | New + replace `AIToolExecutor+Logging` |
| 7 | Create `Sandbox` actor — capability-based authorization | New + consolidate `PathValidator`, `SandboxDecorator`, `PreWritePreventionEngine`, `FileToolWriteApplier` safety checks |
| 8 | Decompose `ToolLoopHandler` into 7 components | Many new files + delete old |
| 9 | Wrap all v1 tools in `Tool` protocol adapters | Modify each `Services/Tools/*.swift` |
| 10 | Delete v2 routing layer (`CoderOrchestrator`, `SequentialScheduler`, `ResourceGovernor`, `WorkerPool`, `ToolLoopGuard`) | Delete ~5 files |
| 11 | Wire `ToolRegistry` in `DependencyContainer`, delete `ConversationToolProvider` | Modify `DependencyContainer`, delete old file |

---

## Key Metrics (Target)

| Metric | Current | Target |
|--------|---------|--------|
| Tool execution time (sequential batch of 4) | ~N * avg (serialized) | ~max(tool1, tool2, ...) (parallel) |
| Log write overhead per tool call | 5 serial Task {} | 1 buffered batch write |
| Watchdog CPU overhead | 200ms polling × N tools | Zero (async suspension) |
| Tool alias tables | 3 copies, out of sync | 1 registry |
| `_raw_args_chunk` parsers | 4 copies | 1 `ArgumentCollector` |
| `ToolLoopHandler` lines | 2,849 | ~800 across 7 components |
| Time to add new tool | 3 files | 1 file (`Tool` conformance + `registry.register()`) |
| Sub-agent parallel execution | Not possible | Native via `ToolScheduler` multi-agent |
