# Architecture v2 — Coder Mode Implementation Blueprint

> **Phase**: Architecture Design. Ready for implementation.
> **Scope**: Coder mode only. Agent mode is future — the architecture is designed so Agent snaps onto this foundation.
> **Goal**: Rock-solid orchestration, tool execution, feedback, and crash recovery.

---

## Table of Contents

1. [File Layout](#1-file-layout)
2. [Component Dependency Graph](#2-component-dependency-graph)
3. [Core Protocols](#3-core-protocols)
4. [Tool Execution Pipeline](#4-tool-execution-pipeline)
5. [Data Flow: Request → Response](#5-data-flow-request--response)
6. [Orchestration (Coder Mode)](#6-orchestration-coder-mode)
7. [Error Handling & Recovery](#7-error-handling--recovery)
8. [Dependency Injection Wiring](#8-dependency-injection-wiring)
9. [Testing Infrastructure](#9-testing-infrastructure)
10. [Migration Strategy](#10-migration-strategy)
11. [Implementation Priorities](#11-implementation-priorities)
12. [Files to Create / Modify / Delete](#12-files-to-create--modify--delete)
13. [Execution Model](#13-execution-model--concurrency-isolation-resource-governance-recovery)
14. [Tool Migration Plan](#14-tool-migration-plan--port-rewrite-or-build)

---

## 1. File Layout

All new code goes into `Services/Tooling/` — a clean directory with no dependencies on old code.

```
osx-ide/Services/
├── Tooling/                              ← NEW: All new tool architecture
│   ├── ToolDefinition.swift              ← Tool metadata (replaces AITool)
│   ├── ToolCapability.swift              ← Capability enum
│   ├── ToolSideEffect.swift              ← Side effect enum
│   ├── ToolFeedback.swift                ← Structured feedback envelope (CRITICAL)
│   ├── ToolCall.swift                    ← Parsed tool call from model
│   ├── ToolResult.swift                  ← Execution result
│   ├── Registry/
│   │   ├── ToolRegistry.swift            ← Thread-safe registry
│   │   └── ToolRegistryProtocol.swift    ← Interface
│   ├── Execution/
│   │   ├── ToolExecutor.swift            ← Protocol (single execute())
│   │   ├── RealToolExecutor.swift        ← Actual implementation
│   │   ├── SandboxDecorator.swift        ← Sandbox + read-before-write
│   │   ├── TelemetryDecorator.swift      ← Timing + logging wrapper
│   │   └── LegacyToolAdapter.swift       ← Wraps old AITool into new ToolDefinition
│   ├── Scheduling/
│   │   ├── SequentialScheduler.swift     ← Coder mode: sequential batch
│   │   ├── ToolScheduler.swift           ← MOVE from Services/ (actor, read/write locks)
│   │   └── AsyncSemaphore.swift          ← MOVE from Services/
│   ├── Feedback/
│   │   └── ToolFeedbackFormatter.swift   ← Formats ToolFeedback for model
│   ├── Orchestration/
│   │   └── CoderOrchestrator.swift       ← Coder mode orchestrator (single turn + tools)
│   ├── Guard/
│   │   └── ToolLoopGuard.swift           ← EXTRACT from ToolLoopHandler (repetition detection)
│   ├── Infrastructure/
│   │   ├── ToolFileAccessLedger.swift    ← REWRITE: turn-aware read tracking
│   │   ├── PathValidator.swift           ← MOVE from Services/ (with v2 enhancements)
│   │   ├── ToolInvocationContext.swift   ← REWRITE
│   │   └── ToolFileExclusion.swift       ← MOVE from Core/
│   └── Adapters/
│       ├── ToolFormatAdapter.swift       ← Protocol for model-specific format
│       ├── OpenRouterToolAdapter.swift   ← OpenAI-compatible format
│       └── GemmaToolAdapter.swift        ← Gemma native format
│
├── Tools/                                ← NEW implementations (same location)
│   ├── ReadFileTool.swift                ← REWRITE to new ToolDefinition
│   ├── WriteFileTool.swift               ← REWRITE to new ToolDefinition
│   ├── ReplaceInFileTool.swift           ← REWRITE to new ToolDefinition
│   ├── PatchFileTool.swift               ← NEW: high-performance line-numbered patches
│   ├── DeleteFileTool.swift              ← REWRITE to new ToolDefinition
│   ├── ListFilesTool.swift               ← REWRITE
│   ├── FindFileTool.swift                ← REWRITE
│   ├── GrepTool.swift                    ← REWRITE
│   ├── SearchProjectTool.swift           ← REWRITE
│   ├── ... (all 25 tools, rewritten one at a time)
│
└── Orchestration/                        ← KEEP existing (for Agent mode future)
    ├── OrchestrationGraph.swift
    ├── OrchestrationState.swift
    └── ...
```

---

## 2. Component Dependency Graph

```
                    ┌─────────────────────────────┐
                    │     CoderOrchestrator        │
                    │  (single turn + tools)       │
                    └──────────┬──────────────────┘
                               │ depends on
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                    ToolExecutor (protocol)                   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              TelemetryDecorator                       │   │
│  │  (wraps inner, records timing + logs)                 │   │
│  └──────────────────────┬───────────────────────────────┘   │
│                         │ wraps                             │
│  ┌──────────────────────▼───────────────────────────────┐   │
│  │              SandboxDecorator                         │   │
│  │  (read-before-write check, path validation)           │   │
│  └──────────────────────┬───────────────────────────────┘   │
│                         │ wraps                             │
│  ┌──────────────────────▼───────────────────────────────┐   │
│  │              RealToolExecutor                         │   │
│  │  (finds tool in registry, executes, returns result)   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         │ uses
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  ┌─────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ ToolRegistry     │  │ Sequential     │  │ ToolScheduler│ │
│  │ (thread-safe)    │  │ Scheduler      │  │ (actor)      │ │
│  └─────────────────┘  └────────────────┘  └──────────────┘ │
│  ┌─────────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ ToolFileAccess   │  │ PathValidator  │  │ ToolLoop     │ │
│  │ Ledger           │  │ (v2)           │  │ Guard        │ │
│  └─────────────────┘  └────────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**Key rule**: Dependencies flow DOWN. `CoderOrchestrator` depends on `ToolExecutor`. `ToolExecutor` depends on `ToolRegistry` + schedulers. No cycles.

---

## 3. Core Protocols

### 3.1 ToolDefinition

```swift
/// Immutable metadata for a tool. Registered once, used everywhere.
struct ToolDefinition: Sendable, Codable {
    // Identity
    let name: String
    let displayName: String?
    
    // Schema (model-facing)
    let description: String
    let parameters: JSONSchema              // typed JSON Schema, not [String: Any]
    
    // Capabilities & Side Effects
    let capabilities: Set<ToolCapability>    // for registry queries
    let sideEffects: Set<ToolSideEffect>     // for sandbox enforcement
    
    // Mode Availability
    let allowedModes: Set<AgentMode>         // .chat, .coder, .agent
    
    // Prompt Material
    let promptMaterial: PromptMaterial       // concise, standard, comprehensive variants
    let feedbackFormat: FeedbackDocumentation // expected feedback format
    let errorCodes: [ErrorCodeDocumentation]  // error codes + recovery paths
    let fallbackChain: [FallbackTool]         // what to try on failure
    
    // Execution Configuration
    let defaultTimeout: TimeInterval
    let supportsStreaming: Bool
    let isolation: ToolIsolation              // concurrent, pathIsolated, sessionIsolated, globallySerial
    
    // Execution (the actual implementation)
    let execute: @Sendable (ToolExecutionRequest) async throws -> ToolFeedback
    
    // Factory
    static func command(
        name: String,
        description: String,
        parameters: JSONSchema,
        capabilities: Set<ToolCapability>,
        sideEffects: Set<ToolSideEffect>,
        execute: @Sendable @escaping (ToolExecutionRequest) async throws -> ToolFeedback
    ) -> ToolDefinition
    
    static func query(
        name: String,
        description: String,
        parameters: JSONSchema,
        capabilities: Set<ToolCapability>,
        contentFormat: ToolContentFormat,
        execute: @Sendable @escaping (ToolExecutionRequest) async throws -> ToolFeedback
    ) -> ToolDefinition
}

struct ToolExecutionRequest: Sendable {
    let toolCall: ToolCall
    let context: ExecutionContext
}

struct ExecutionContext: Sendable {
    let conversationId: String
    let turnId: String                       // unique per model invocation
    let projectRoot: URL
    let mode: AgentMode
    let sandbox: SandboxConfiguration
}
```

### 3.2 ToolFeedback (the structured envelope)

```swift
/// Every tool returns this. Never a raw String.
struct ToolFeedback: Sendable, Codable {
    let status: ToolFeedbackStatus
    let message: String                      // human-readable summary
    let content: ToolContent?                // for query tools
    let error: ToolErrorInfo?                // for failures
}

enum ToolFeedbackStatus: String, Sendable, Codable {
    case success
    case error
    case partial
}

struct ToolErrorInfo: Sendable, Codable {
    let code: String                         // MUTATION_WITHOUT_PRIOR_READ, RESOURCE_BUSY, etc.
    let message: String
    let recoverable: Bool
    let alternatives: [ToolAlternative]?
}

struct ToolAlternative: Sendable, Codable {
    let description: String
    let suggestion: String
    let toolName: String?
    let arguments: [String: String]?
}

struct ToolContent: Sendable, Codable {
    let data: ToolContentData
    let metadata: [String: String]?
}

enum ToolContentData: Sendable, Codable {
    case text(String)
    case json([String: AnyCodable])
    case items([ToolContentItem])
    case empty
}

struct ToolContentItem: Sendable, Codable {
    let label: String
    let description: String?
    let path: String?
    let lineNumber: Int?
    let kind: String?
}
```

### 3.3 ToolRegistry

```swift
protocol ToolRegistryProtocol: Sendable {
    func register(_ tool: ToolDefinition)
    func tool(named: String) -> ToolDefinition?
    func tools(for capabilities: Set<ToolCapability>) -> [ToolDefinition]
    func tools(for mode: AgentMode) -> [ToolDefinition]
    var allTools: [ToolDefinition] { get }
}

actor ToolRegistry: ToolRegistryProtocol {
    private var toolsByName: [String: ToolDefinition] = [:]
    
    func register(_ tool: ToolDefinition) {
        precondition(toolsByName[tool.name] == nil, "Duplicate tool: \(tool.name)")
        toolsByName[tool.name] = tool
    }
    
    func tool(named: String) -> ToolDefinition? {
        toolsByName[named]
    }
    
    func tools(for capabilities: Set<ToolCapability>) -> [ToolDefinition] {
        toolsByName.values.filter { !$0.capabilities.isDisjoint(with: capabilities) }
    }
    
    func tools(for mode: AgentMode) -> [ToolDefinition] {
        toolsByName.values.filter { $0.allowedModes.contains(mode) }
    }
    
    var allTools: [ToolDefinition] {
        Array(toolsByName.values)
    }
}
```

### 3.4 Tool Executor (Decorator Chain)

```swift
protocol ToolExecutor: Sendable {
    func execute(request: ToolExecutionRequest) async throws -> ToolFeedback
}
```

No other methods. The decorator chain adds all cross-cutting concerns.

### 3.5 ToolFormatAdapter

```swift
protocol ToolFormatAdapter: Sendable {
    /// Convert internal tool definitions to model-specific JSON schema
    func encodeTools(_ tools: [ToolDefinition]) -> [[String: Any]]
    
    /// Convert model response into internal ToolCall
    func decodeToolCalls(from response: Any) throws -> [ToolCall]
    
    /// Convert internal ToolFeedback into model-friendly string
    func encodeFeedback(_ feedback: ToolFeedback) -> String
}
```

---

## 4. Tool Execution Pipeline

Step by step for a single tool call:

```
1. CoderOrchestrator receives model response with tool_calls
       │
2. ToolFormatAdapter.decodeToolCalls() → [ToolCall]
       │
3. ToolFeedbackFormatter pre-fills system prompt with expected formats
       │
4. For each tool call (sequential in Coder mode):
       │
       ├── 4a. SequentialScheduler picks next call
       │
       ├── 4b. TelemetryDecorator: start timer
       │
       ├── 4c. SandboxDecorator:
       │       ├── Check: is this tool allowed in Coder mode? (capability check)
       │       ├── Check: is this a mutation on existing file? → read-before-write check
       │       ├── If blocked: return ToolFeedback with status .error + alternatives
       │       └── If allowed: pass through
       │
       ├── 4d. RealToolExecutor:
       │       ├── ToolRegistry.tool(named: "read_file") → ToolDefinition
       │       ├── ToolScheduler.runReadTask / runWriteTask (concurrency control)
       │       ├── Call tool definition's execute() closure
       │       └── Return ToolFeedback
       │
       ├── 4e. TelemetryDecorator: record timing, log feedback
       │
       └── 4f. ToolFileAccessLedger.recordRead(path, turnId) if applicable
       │
5. ToolFormatAdapter.encodeFeedback() → model-friendly string for each result
       │
6. Feed results back to model → model continues or finishes
```

---

## 5. Data Flow: Request → Response

```
User types: "Add error handling to NetworkManager.swift"
  │
  ▼
ConversationManager
  │
  ├── Creates SendRequest { mode: .coder, message: "..." }
  │
  ▼
CoderOrchestrator.handle(request:)
  │
  ├── Step 1: Query ToolRegistry for Coder-mode tools
  │           → ToolFormatAdapter.encodeTools() → JSON schema
  │
  ├── Step 2: Call AI model with [system prompt + tools schema + user message]
  │
  ├── Step 3: Model returns AIServiceResponse
  │           → ToolFormatAdapter.decodeToolCalls() → [ToolCall]
  │
  ├── Step 4: If toolCalls.isEmpty → return text response (done)
  │
  ├── Step 5: Execute tools via ToolExecutor chain
  │           → SequentialScheduler.schedule(toolCalls, executor)
  │               → For each call:
  │                   ToolFileAccessLedger.startTurn(turnId)
  │                   result = await executor.execute(request)
  │                   ToolFileAccessLedger.endTurn(turnId)
  │           → Returns [ToolFeedback]
  │
  ├── Step 6: Format results via ToolFormatAdapter.encodeFeedback()
  │
  ├── Step 7: Feed [feedback messages] back to AI model
  │
  ├── Step 8: Model returns final text response (or more tool calls)
  │
  └── Step 9: Return ResponseStream to ConversationManager
      │
      ▼
  User sees: "Added error handling with Result type..."
```

---

## 6. Orchestration (Coder Mode)

### 6.1 CoderOrchestrator

```swift
@MainActor
final class CoderOrchestrator {
    private let toolRegistry: ToolRegistryProtocol
    private let toolExecutor: ToolExecutor          // decorator chain
    private let scheduler: SequentialScheduler      // only for Coder mode
    private let adapter: ToolFormatAdapter          // model-specific format
    private let feedbackFormatter: ToolFeedbackFormatter
    private let accessLedger: ToolFileAccessLedger
    private let loopGuard: ToolLoopGuard
    private let aiService: AIServiceProtocol        // the AI model
    
    func handle(
        request: SendRequest,
        conversationId: String
    ) async -> ResponseStream {
        // 1. Get tools for Coder mode
        let tools = toolRegistry.tools(for: .coder)
        
        // 2. Encode tools to model format
        let toolSchemas = adapter.encodeTools(tools)
        
        // 3. Build messages with tool schemas
        let messages = buildMessages(
            request: request,
            toolSchemas: toolSchemas,
            feedbackDocs: feedbackFormatter.buildDocumentation(for: tools)
        )
        
        // 4. Call AI model
        var response = try await aiService.complete(messages: messages, tools: toolSchemas)
        
        // 5. Tool loop (single turn for Coder — one iteration)
        guard let toolCalls = adapter.decodeToolCalls(from: response), !toolCalls.isEmpty else {
            return ResponseStream.text(response.content)
        }
        
        // 6. Check for repetition / looping
        guard !loopGuard.shouldAbort(toolCalls: toolCalls, turnHistory: turnHistory) else {
            return ResponseStream.text("I'm having trouble completing this task. Could you rephrase?")
        }
        
        // 7. Execute tools
        let turnId = UUID().uuidString
        accessLedger.startTurn(turnId)
        
        let results = try await scheduler.schedule(
            toolCalls: toolCalls,
            executor: toolExecutor,
            context: ExecutionContext(
                conversationId: conversationId,
                turnId: turnId,
                projectRoot: request.projectRoot,
                mode: .coder,
                sandbox: .coder
            )
        )
        
        accessLedger.endTurn(turnId)
        
        // 8. Format results for model
        let feedbackMessages = results.map { adapter.encodeFeedback($0) }
        
        // 9. Feed back to model for final response
        let finalResponse = try await aiService.complete(
            messages: messages + feedbackMessages,
            tools: nil    // no more tools — single turn
        )
        
        return ResponseStream.text(finalResponse.content)
    }
}
```

### 6.2 SequentialScheduler

```swift
actor SequentialScheduler {
    private let toolScheduler: ToolScheduler  // read/write concurrency control
    
    func schedule(
        toolCalls: [ToolCall],
        executor: ToolExecutor,
        context: ExecutionContext
    ) async throws -> [ToolFeedback] {
        var results: [ToolFeedback] = []
        results.reserveCapacity(toolCalls.count)
        
        for call in toolCalls {
            let request = ToolExecutionRequest(toolCall: call, context: context)
            let feedback = try await executor.execute(request: request)
            results.append(feedback)
        }
        
        return results
    }
}
```

Simple. Sequential. One at a time. The `ToolScheduler` provides internal concurrency (read semaphore, write locks). The `SequentialScheduler` just iterates.

### 6.3 ToolLoopGuard (extracted from ToolLoopHandler)

```swift
/// Pure actor that detects looping/repettive tool execution.
/// Extracted from the 2,775-line ToolLoopHandler.
actor ToolLoopGuard {
    private var previousToolSignatures: [String: Set<String>] = [:]  // turnId → signatures
    
    /// Check if we should abort due to repetition
    func shouldAbort(toolCalls: [ToolCall], turnHistory: [ToolFeedback]) -> Bool {
        let signatures = toolCalls.map { $0.signature }
        let previous = previousToolSignatures.values.flatMap { $0 }
        
        // Same exact batch 3+ times? Abort.
        let matchCount = previous.filter { signatures.contains($0) }.count
        if matchCount >= 3 { return true }
        
        // Record current signatures
        let turnId = UUID().uuidString
        previousToolSignatures[turnId] = Set(signatures)
        return false
    }
    
    func reset(conversationId: String) {
        previousToolSignatures.removeAll()
    }
}
```

---

## 7. Error Handling & Recovery

### 7.1 Error Boundary Map

```
Layer 1: Model Error (bad JSON, no response, timeout)
  ├── AI service throws → CoderOrchestrator catches
  ├── Action: Retry with stricter prompt (max 2 retries)
  └── If all retries fail: return user-friendly error message

Layer 2: Tool Execution Error (file not found, permission denied)
  ├── Tool returns ToolFeedback(status: .error) — NOT a throw
  ├── Model sees the error and decides what to do
  ├── Error includes alternatives for recovery
  └── No crash, no exception — just structured feedback

Layer 3: Framework Error (registry lookup failed, scheduler busy)
  ├── ToolExecutor throws → decorator catches
  ├── Action: Convert to ToolFeedback with .error status
  └── Model sees it as a tool result, not a crash

Layer 4: Infrastructure Error (disk full, DB locked)
  ├── Rare, but catastrophic
  ├── Action: Log full context, return error to user
  └── Do NOT retry (would make it worse)
```

### 7.2 Error Recovery Flow

```
Tool fails → ToolFeedback(status: .error, error: ToolErrorInfo)
  │
  ├── error.recoverable == true:
  │     Model sees alternatives array
  │     "Try: read_file first" or "Try: rm -f via run_command"
  │     Model picks an alternative and retries
  │
  ├── error.recoverable == false:
  │     Model reports to user: "Can't delete this file (it's locked)"
  │     User decides what to do
  │
  └── error.code == "MUTATION_WITHOUT_PRIOR_READ":
        Model reads the file first, then retries the mutation
        (This is the most common recoverable error in Coder mode)
```

### 7.3 Crash Recovery

Since we're git-native (section 17.5), crash recovery is:

```swift
protocol CrashRecovery: Sendable {
    /// On app launch after crash:
    /// 1. Check for in-progress agent session branch
    /// 2. If found: git status to see what was changed
    /// 3. Present user with: "Recover session?" prompt
    /// 4. If yes: continue from last commit
    /// 5. If no: git reset --hard to pre-session state
    
    func checkForInProgressSession() async -> InProgressSession?
    func recoverSession(_ session: InProgressSession) async throws
    func discardSession(_ session: InProgressSession) async throws
}

struct InProgressSession: Sendable {
    let branchName: String
    let lastCommitMessage: String
    let lastCommitDate: Date
    let uncommittedChanges: Bool
    let changedFiles: [String]
}
```

For Coder mode (single turn), crashes are simpler:
- If crash happens BEFORE tool execution: nothing to recover
- If crash happens DURING tool execution: some files may be partially written
- On next launch: `git status` shows modified files. User can `git checkout` to revert
- No special recovery needed for Coder — the turn is short enough that manual recovery is fine

---

## 8. Dependency Injection Wiring

### 8.1 DependencyContainer Updates

```swift
extension DependencyContainer {
    /// Create the new tooling stack (alongside existing old stack)
    func makeToolingStack() -> ToolingStack {
        // 1. Registry
        let registry = ToolRegistry()
        
        // 2. Register built-in tools
        ToolRegistrar.registerAllTools(in: registry)
        
        // 3. Infrastructure
        let accessLedger = ToolFileAccessLedger()
        let pathValidator = PathValidator(projectRoot: ...)
        let fileExclusion = ToolFileExclusion(projectRoot: ...)
        let scheduler = ToolScheduler()
        let loopGuard = ToolLoopGuard()
        
        // 4. Build decorator chain
        let realExecutor = RealToolExecutor(
            registry: registry,
            scheduler: scheduler,
            accessLedger: accessLedger,
            pathValidator: pathValidator
        )
        
        let sandboxDecorator = SandboxDecorator(
            inner: realExecutor,
            accessLedger: accessLedger,
            configuration: .coder  // Coder mode sandbox rules
        )
        
        let telemetryDecorator = TelemetryDecorator(
            inner: sandboxDecorator,
            logger: logger
        )
        
        // 5. Scheduler
        let sequentialScheduler = SequentialScheduler(toolScheduler: scheduler)
        
        // 6. Adapter
        let adapter = OpenRouterToolAdapter()  // or GemmaToolAdapter for local
        
        // 7. Orchestrator
        let orchestrator = CoderOrchestrator(
            toolRegistry: registry,
            toolExecutor: telemetryDecorator,
            scheduler: sequentialScheduler,
            adapter: adapter,
            feedbackFormatter: feedbackFormatter,
            accessLedger: accessLedger,
            loopGuard: loopGuard,
            aiService: aiService
        )
        
        return ToolingStack(
            registry: registry,
            orchestrator: orchestrator,
            executor: telemetryDecorator,
            adapter: adapter
        )
    }
}

struct ToolingStack {
    let registry: ToolRegistryProtocol
    let orchestrator: CoderOrchestrator
    let executor: ToolExecutor
    let adapter: ToolFormatAdapter
}
```

### 8.2 Old/New Coexistence

```swift
// ConversationManager decides which path to use:
if useNewArchitecture {
    let stack = container.makeToolingStack()
    return try await stack.orchestrator.handle(request: request, conversationId: id)
} else {
    // Old path (existing ConversationSendCoordinator flow)
    return try await legacyHandle(request: request)
}
```

The flag `useNewArchitecture` starts as `false` and is toggled to `true` for individual tools as they're migrated.

---

## 9. Testing Infrastructure

### 9.1 Test Doubles

```swift
// In-memory file system for tool tests
final class InMemoryFileSystem: FileSystemReader, FileSystemWriter {
    private var files: [String: Data] = [:]
    private var errors: [String: Error] = [:]  // inject faults
    
    func readFile(at path: String) async throws -> Data {
        if let error = errors[path] { throw error }
        guard let data = files[path] else { throw FileError.notFound }
        return data
    }
    
    func writeFile(data: Data, to path: String) async throws {
        if let error = errors[path] { throw error }
        files[path] = data
    }
    
    // Inject a fault for testing error paths
    func injectFault(path: String, error: Error) {
        errors[path] = error
    }
}

// No-op telemetry for tests
struct NoopTelemetry: ToolTelemetry {
    func recordExecution(call: ToolCall, duration: TimeInterval, feedback: ToolFeedback) {}
}

// In-memory access ledger (no actor isolation needed in tests)
final class InMemoryAccessLedger: ToolFileAccessLedgerProtocol {
    private var reads: [String: Set<String>] = [:]
    
    func recordRead(path: String, turnId: String) {
        reads[turnId, default: []].insert(path)
    }
    
    func hasRead(path: String, turnId: String) -> Bool {
        reads[turnId]?.contains(path) ?? false
    }
}
```

### 9.2 Test Categories

```
┌─────────────────────────────────────────────────────┐
│                   UNIT TESTS (fast)                   │
│                                                       │
│  ToolDefinitionTests          — schema generation     │
│  ToolRegistryTests            — query, register       │
│  SandboxDecoratorTests        — read-before-write     │
│  SequentialSchedulerTests     — ordering, errors      │
│  ToolFeedbackFormatterTests   — format correctness    │
│  ToolLoopGuardTests           — repetition detection  │
│  PathValidatorTests           — path resolution       │
│  ToolFileAccessLedgerTests    — turn tracking         │
│  ToolExecutionRequestTests    — context building      │
│                                                       │
│  Per-tool tests (one per tool):                       │
│    ReadFileToolTests          — read, line range      │
│    WriteFileToolTests         — write, overwrite      │
│    PatchFileToolTests         — hunk application      │
│    ...                         (25 test files)        │
│                                                       │
├─────────────────────────────────────────────────────┤
│                INTEGRATION TESTS (medium)              │
│                                                       │
│  RealToolExecutorTests        — full chain, mock AI   │
│  CoderOrchestratorTests       — single turn flow      │
│  DecoratorChainTests          — sandbox + telemetry   │
│                                                       │
├─────────────────────────────────────────────────────┤
│              END-TO-END TESTS (slow, few)              │
│                                                       │
│  CoderModeFlowTests           — "add error handling"  │
│  ToolRecoveryFlowTests        — "file busy" → recover │
│  CrashRecoveryTests           — git state management  │
└─────────────────────────────────────────────────────┘
```

---

## 10. Migration Strategy

### Phase 1: Foundation (parallel, non-breaking)
1. Create `Services/Tooling/` directory
2. Implement value types: `ToolDefinition`, `ToolFeedback`, `ToolCall`, `ToolCapability`, `ToolSideEffect`
3. Implement `ToolRegistry`
4. Implement `ToolExecutor` protocol + `RealToolExecutor`
5. Implement `SandboxDecorator` with read-before-write
6. Implement `SequentialScheduler`
7. Implement `ToolFormatAdapter` protocol + `OpenRouterToolAdapter`
8. Implement `ToolFeedbackFormatter`
9. Implement `ToolFileAccessLedger` (turn-aware)
10. Write unit tests for everything above
11. **No old code is touched. Old tools continue to work.**

### Phase 2: First Tools Migrated
1. Port `ReadFileTool` to new `ToolDefinition` format
2. Register it in the new `ToolRegistry` alongside old registry
3. Wrap old `WriteFileTool` via `LegacyToolAdapter` for testing
4. Implement `CoderOrchestrator` using only migrated tools
5. Run Coder mode with just read_file → verify it works
6. Port `WriteFileTool`, `ReplaceInFileTool`, `ListFilesTool`
7. Each tool: rewrite → test → register → verify

### Phase 3: Coder Mode Cutover
1. All 25 tools migrated to new format
2. `CoderOrchestrator` handles all Coder mode requests
3. Old `ConversationToolProvider` is bypassed for Coder mode
4. Old `AIToolExecutor` path is still available for Agent mode (unchanged)
5. `ToolLoopHandler` still handles Agent mode (old path, not yet migrated)

### Phase 4: Agent Mode (future)
1. Build `DAGScheduler` on top of existing foundation
2. Build `BackgroundJobManager` + sub-agent tools
3. Build `OrchestratorGraph` v2 (true DAG, not linear)
4. Agent mode snaps onto the same `ToolExecutor`, `ToolRegistry`, `SandboxDecorator`

---

## 11. Implementation Priorities

### Must Have (Coder Mode MVP)

```
Priority 1: ToolDefinition + ToolRegistry
  Without these, nothing else works.

Priority 2: ToolFeedback (structured envelope)
  Without this, agents can't recover from errors.

Priority 3: RealToolExecutor + SequentialScheduler
  The core execution path.

Priority 4: SandboxDecorator (read-before-write + path validation)
  Safety net for Coder mode.

Priority 5: CoderOrchestrator (basic version)
  Single turn, one tool loop iteration.
  Works with 1 tool first (read_file).

Priority 6: ToolFormatAdapter (OpenRouter)
  Model needs to understand the tools.

Priority 7: First 5 migrated tools
  read_file, write_file, list_files, grep, search_project
  Enough to handle 80% of daily coding tasks.
```

### Nice to Have (Coder Mode Complete)

```
Priority 8: All 25 tools migrated
Priority 9: ToolLoopGuard (repetition detection)
Priority 10: TelemetryDecorator
Priority 11: PatchFileTool
Priority 12: LegacyToolAdapter (for any unported tools)
Priority 13: GemmaToolAdapter (local model support)
```

### Future (Agent Mode)

```
DAGScheduler, BackgroundJobManager, SubAgentChannel,
OrchestratorGraph v2, GitCheckpointService
```

---

## 13. Execution Model — Concurrency, Isolation, Resource Governance, Recovery

**This is the hardest problem in the architecture. The wrong choice here causes crashes, starvation, deadlocks, and unrecoverable state.**

### 13.1 Decision: Worker Pool Actor (Not Single Actor, Not Per-Tool Actor)

| Option | Pro | Con | Verdict |
|--------|-----|-----|---------|
| **Single actor** (one serial queue) | Simple, no races | Sequential bottleneck, one slow tool blocks everything | ❌ |
| **Per-tool actor** (each tool is its own actor) | True parallelism | Unbounded resource usage, complex lifecycle, swarm = death | ❌ |
| **Worker pool** (fixed N workers, dispatch tools to available workers) | Controlled parallelism, resource budgeting, dead worker replacement | Slightly more complex | ✅ |

**Worker pool architecture**:

```
                     ┌──────────────────────┐
                     │   SequentialScheduler  │  (or DAGScheduler for Agent)
                     │   (dispatches tools)   │
                     └──────────┬───────────┘
                                │
                                ▼
                     ┌──────────────────────┐
                     │    WorkerPool         │  ← actor with fixed N workers
                     │                       │
                     │  ┌────┐ ┌────┐ ┌────┐ │
                     │  │ W1 │ │ W2 │ │ W3 │ │  ← each worker runs one tool
                     │  └────┘ └────┘ └────┘ │
                     │  ··· (up to N)        │
                     └──────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    ▼                       ▼
           ┌──────────────┐       ┌──────────────┐
           │ Safe tools    │       │ Dangerous     │
           │ (in-process)  │       │ tools (spawn) │
           │ read_file,    │       │ run_command,  │
           │ write_file,   │       │ web_browse    │
           │ grep, search  │       │               │
           └──────────────┘       └──────────────┘
```

```swift
/// Controls how many tools run concurrently and their resource budgets.
/// This is the SINGLE point where concurrency, memory, and I/O are governed.
actor WorkerPool {
    private let workers: [Worker]
    private var availableWorkers: Set<Int>
    private var pendingTasks: [TaskPriority: [PendingToolExecution]] = [:]
    
    private let configuration: PoolConfiguration
    
    struct PoolConfiguration: Sendable {
        let maxConcurrentTools: Int          // worker count
        let maxConcurrentReadIO: Int         // disk I/O semaphore
        let maxConcurrentNetworkIO: Int      // network I/O semaphore
        let maxMemoryPerToolBytes: Int       // per-tool RSS limit
        let maxWallTimePerTool: Duration     // timeout
        let toolSpawnStrategy: SpawnStrategy // in-process vs process
    }
    
    static let coder = PoolConfiguration(
        maxConcurrentTools: 4,               // 4 parallel tools max
        maxConcurrentReadIO: 4,              // 4 simultaneous disk reads
        maxConcurrentNetworkIO: 2,           // 2 simultaneous network calls
        maxMemoryPerToolBytes: 50 * 1024 * 1024,  // 50MB per tool
        maxWallTimePerTool: .seconds(30),    // 30s timeout
        toolSpawnStrategy: .smart            // in-process for safe, spawn for dangerous
    )
    
    /// Dispatch a tool to an available worker.
    /// Returns immediately. Worker runs asynchronously.
    func dispatch(
        request: ToolExecutionRequest,
        executor: ToolExecutor
    ) async -> ToolFeedback {
        // 1. Wait for an available worker
        await waitForWorker()
        
        // 2. Assign to worker
        let workerId = claimWorker()
        
        // 3. Run with timeout + budget
        return await withThrowingTaskGroup(of: ToolFeedback.self) { group in
            group.addTask {
                // Run the tool with memory monitoring
                return try await withMemoryBudget(configuration.maxMemoryPerToolBytes) {
                    try await executor.execute(request: request)
                }
            }
            
            group.addTask {
                // Timeout task
                try await Task.sleep(nanoseconds: UInt64(configuration.maxWallTimePerTool.nanoseconds))
                throw ToolError.timedOut(request.toolCall.toolName)
            }
            
            // 4. First task to finish wins
            let result = try await group.next()!
            group.cancelAll()
            releaseWorker(workerId)
            return result
        }
    }
}
```

### 13.2 In-Process vs Spawned Process

**Decision: Smart hybrid. Safe tools run in-process via actors. Dangerous tools spawn as processes.**

```swift
enum SpawnStrategy: Sendable {
    /// Run all tools in-process (simple, no overhead)
    case alwaysInProcess
    
    /// Run all tools as spawned processes (crash isolation, high overhead)
    case alwaysSpawn
    
    /// Choose based on tool side effects (recommended)
    case smart
}

/// ToolDefinition declares its spawn preference:
extension ToolDefinition {
    var recommendedSpawnStrategy: SpawnStrategy {
        if sideEffects.contains(.executesCommand) { return .alwaysSpawn }
        if sideEffects.contains(.makesNetworkRequest) { return .alwaysSpawn }
        return .alwaysInProcess
    }
}
```

| Tool | Strategy | Rationale |
|------|----------|-----------|
| `read_file`, `write_file`, `grep`, `search_project` | **In-process** | Fast, safe, bounded resource usage |
| `patch_file` | **In-process** | Needs fast mmap access |
| `run_command` | **Spawn** | Can consume unlimited CPU/RAM, hang forever |
| `web_browse` | **Spawn** | Network I/O can hang, WebKit can leak memory |
| `web_search` | **In-process** | Bounded HTTP request |

**Spawned tool execution**:

```swift
/// Runs a tool in a separate process.
/// The tool communicates via stdin/stdout (JSON).
/// If the process hangs, we kill it. If it crashes, the IDE is unaffected.
actor SpawnedToolExecutor {
    func execute(
        toolCall: ToolCall,
        definition: ToolDefinition,
        context: ExecutionContext
    ) async throws -> ToolFeedback {
        // 1. Serialize request to JSON
        let requestData = try JSONEncoder().encode(ToolProcessRequest(
            toolName: toolCall.toolName,
            arguments: toolCall.arguments,
            context: ToolProcessContext(projectRoot: context.projectRoot)
        ))
        
        // 2. Spawn process
        let process = Process()
        process.executableURL = toolExecutorURL
        process.arguments = [toolCall.toolName]
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        
        // 3. Set resource limits via setrlimit()
        //    macOS: setrlimit(RLIMIT_CPU, ...), setrlimit(RLIMIT_AS, ...)
        setrlimit(RLIMIT_CPU, 30)  // 30s CPU time
        setrlimit(RLIMIT_AS, 100 * 1024 * 1024)  // 100MB address space
        
        try process.run()
        
        // 4. Send request, read response
        try process.standardInput!.write(contentsOf: requestData)
        process.standardInput!.close()
        
        let responseData = try await process.standardOutput!.readToEndAsync()
        
        // 5. If process exited with error, handle
        guard process.terminationStatus == 0 else {
            return ToolFeedback(
                status: .error,
                message: "Tool process crashed (exit code \(process.terminationStatus))",
                content: nil,
                error: ToolErrorInfo(
                    code: "PROCESS_CRASHED",
                    message: "The tool process exited with status \(process.terminationStatus)",
                    recoverable: true,
                    alternatives: nil
                )
            )
        }
        
        return try JSONDecoder().decode(ToolFeedback.self, from: responseData)
    }
}
```

### 13.3 Resource Governance — Surviving the Swarm

**Problem**: If we fire 100 concurrent tool calls (swarm), we need to survive without:
- Starving CPU (OS becomes unresponsive)
- Exhausting RAM (OOM kills the IDE)
- Saturating disk I/O (everything slows to a crawl)
- Saturating network (API calls timeout)

**Solution**: Four independent resource governors, each with hard limits.

```
┌─────────────────────────────────────────────────────┐
│                  ResourceGovernor                    │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │ CPU Governor  │  │ RAM Governor │                 │
│  │ Worker pool   │  │ Per-tool max │                 │
│  │ cap: 4/8     │  │ + total max  │                 │
│  └──────────────┘  └──────────────┘                 │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │ Disk I/O Gov  │  │ Network Gov  │                 │
│  │ Read sema: 4  │  │ Connections: │                 │
│  │ Write: 1/file │  │ 2 simult.   │                 │
│  └──────────────┘  └──────────────┘                 │
└─────────────────────────────────────────────────────┘
```

```swift
/// Single point of resource governance.
/// All tool execution MUST go through this.
actor ResourceGovernor {
    // ── CPU ──
    private let workerPool: WorkerPool
    
    // ── RAM ──
    private var totalMemoryAllocated: Int = 0
    private var memoryByTool: [String: Int] = [:]
    private let maxTotalMemory: Int
    
    // ── Disk I/O ──
    private let readSemaphore: AsyncSemaphore  // max concurrent reads
    private let writeLocks: AsyncLockMap<String>  // one write per file
    
    // ── Network ──
    private let networkSemaphore: AsyncSemaphore  // max concurrent network calls
    
    init(configuration: PoolConfiguration) {
        self.workerPool = WorkerPool(configuration: configuration)
        self.maxTotalMemory = configuration.maxTotalMemoryBytes
        self.readSemaphore = AsyncSemaphore(value: configuration.maxConcurrentReadIO)
        self.networkSemaphore = AsyncSemaphore(value: configuration.maxConcurrentNetworkIO)
        self.writeLocks = AsyncLockMap()
    }
    
    /// Execute a tool with full resource governance.
    /// This is the ONLY way tools should be executed.
    func execute(
        request: ToolExecutionRequest,
        executor: ToolExecutor
    ) async -> ToolFeedback {
        // 1. Check memory budget before starting
        guard totalMemoryAllocated < maxTotalMemory else {
            return ToolFeedback(
                status: .error,
                message: "System is at memory capacity. Please wait for running tools to complete.",
                content: nil,
                error: ToolErrorInfo(code: "RESOURCE_EXHAUSTED_MEMORY", ...)
            )
        }
        
        // 2. Wait for CPU slot (worker pool)
        let feedback = await workerPool.dispatch(request: request, executor: executor)
        
        // 3. Release resources
        return feedback
    }
    
    /// Schedule a read I/O operation (honors read concurrency cap)
    func readIO<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        await readSemaphore.wait()
        defer { Task { await readSemaphore.signal() } }
        return try await operation()
    }
    
    /// Schedule a write I/O operation (honors per-file write lock)
    func writeIO<T>(file: String, _ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        await writeLocks.lock(for: file)
        defer { Task { await writeLocks.unlock(for: file) } }
        return try await operation()
    }
    
    /// Schedule a network I/O operation
    func networkIO<T>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        await networkSemaphore.wait()
        defer { Task { await networkSemaphore.signal() } }
        return try await operation()
    }
    
    /// Track memory allocation for a tool
    func allocateMemory(toolId: String, bytes: Int) {
        totalMemoryAllocated += bytes
        memoryByTool[toolId] = bytes
    }
    
    /// Release memory when tool completes
    func releaseMemory(toolId: String) {
        if let bytes = memoryByTool.removeValue(forKey: toolId) {
            totalMemoryAllocated -= bytes
        }
    }
}
```

### 13.4 Graceful Recovery — Five Failure Modes

#### Failure Mode 1: Tool Crash (in-process actor)

```swift
// Worker actor catches all errors from tool execution.
// If the tool crashes, the worker catches the error and returns ToolFeedback.
// The worker itself survives and can run the next tool.

// Inside WorkerPool.dispatch():
do {
    return try await executor.execute(request: request)
} catch is CancellationError {
    return ToolFeedback(
        status: .error,
        message: "Tool execution cancelled: \(request.toolCall.toolName)",
        error: ToolErrorInfo(code: "CANCELLED", recoverable: true, alternatives: nil)
    )
} catch let error as ToolError {
    return ToolFeedback(
        status: .error,
        message: error.message,
        error: ToolErrorInfo(code: error.code, recoverable: error.recoverable, alternatives: error.alternatives)
    )
} catch {
    return ToolFeedback(
        status: .error,
        message: "Unexpected error: \(error.localizedDescription)",
        error: ToolErrorInfo(code: "UNEXPECTED", recoverable: true, alternatives: nil)
    )
}
```

**Key insight**: Tools NEVER throw to the orchestrator. They ALWAYS return `ToolFeedback`. The error is handled inside the worker, not propagated up.

#### Failure Mode 2: Tool Crash (spawned process)

```
Process crashes → 
  SpawnedToolExecutor detects exit code != 0 →
  Returns ToolFeedback(status: .error, code: PROCESS_CRASHED) →
  Model sees the error → retries or reports to user

If process HANGS (no output for 30s):
  Timeout task fires first →
  process.kill() →
  Returns ToolFeedback(status: .error, code: TIMEOUT)
```

#### Failure Mode 3: IDE Crash

```
IDE crashes →
  On next launch:
    ConversationManager loads last conversation from persistence
    Git shows uncommitted changes from in-progress session
    App presents: "Recover last session?" dialog
    If yes: continue from last git commit
    If no: git reset --hard to pre-session state
    Conversation history is preserved regardless
```

**No custom recovery needed.** Git handles file state. `ConversationManager` handles conversation state. The two are independent.

#### Failure Mode 4: Lock Contention / Deadlock

```
Scenario: Tool A holds write lock on file X, Tool B holds write lock on file Y.
          Tool A needs file Y, Tool B needs file X. Deadlock.

Solution: Lock hierarchy + timeout:
  - All file locks use ToolScheduler (existing) with timeout
  - If a lock isn't acquired within 10s, the tool fails with LOCK_TIMEOUT
  - The tool releases all held locks and reports error
  - Model retries the tool call (which will succeed because locks are released)
  
  Additionally: write lock acquisition always tries a non-blocking lock first.
  If it fails, it queues and continues to the NEXT tool. No tool blocks waiting for a lock.
```

#### Failure Mode 5: Repeated Tool Failures

```
ToolLoopGuard (from section 6.3) tracks:
  - Same tool call signature repeated 3+ times → abort turn
  - Same error code returned 3+ times → abort turn
  - Same tool batch repeated 2+ times → abort turn

When aborting:
  - CoderOrchestrator returns partial results to user
  - Message: "I tried 3 times but failed. Here's what I got done before the error."
  - User can inspect the error and decide what to do
```

### 13.5 Resource Limits Summary

| Resource | Coder Mode | Agent Mode | Enforcement |
|----------|-----------|------------|-------------|
| Concurrent tools | 4 | 8 | Worker pool size |
| Concurrent disk reads | 4 | 8 | AsyncSemaphore |
| Concurrent disk writes per file | 1 | 1 | AsyncLockMap (per path) |
| Concurrent network requests | 2 | 4 | AsyncSemaphore |
| Per-tool memory | 50MB | 100MB | setrlimit (spawned) / monitoring (in-process) |
| Total memory | 200MB | 500MB | ResourceGovernor tracking |
| Per-tool wall time | 30s | 5min | Task timeout |
| Tool retries per call | 3 | 5 | ToolLoopGuard |
| Lock timeout | 10s | 30s | ToolScheduler |

### 13.6 File System Impact

The `ToolScheduler` (from existing code) handles per-file write serialization. The `ResourceGovernor.readIO()` and `writeIO()` methods are what tools call instead of directly accessing the file system:

```swift
// Tool implementation:
func execute(request: ToolExecutionRequest) async throws -> ToolFeedback {
    let data = try await governor.readIO {
        try fileSystem.readFile(at: url)
    }
    // ... process data ...
}
```

This means:
- Disk I/O is always governed, never unbounded
- Tools don't need to think about concurrency — they just call `governor.readIO {}`
- The governor is injected via the `ExecutionContext`

### 13.7 System Prompt for Resource Awareness

The model needs to know about resource limits so it can make intelligent decisions:

```
## Resource Limits

- Max 4 tools run at the same time. If tools are waiting, be patient.
- Each tool has 30 seconds to complete. If a tool times out, try a different approach.
- Network requests are limited to 2 at a time.
- Memory is limited. Don't try to read very large files (>50MB) in a single call.
- If a tool fails with RESOURCE_EXHAUSTED, wait for other tools to finish, then retry.
- If a tool fails with the SAME error 3 times, stop trying that approach and try something different.
```

---

## 12. Files to Create / Modify / Delete

### New Files (create in `Services/Tooling/`)

| File | Lines (est.) | Description |
|------|-------------|-------------|
| `ToolDefinition.swift` | 80 | Value type + factory methods |
| `ToolCapability.swift` | 30 | Capability enum (12 cases) |
| `ToolSideEffect.swift` | 20 | Side effect enum (8 cases) |
| `ToolFeedback.swift` | 120 | Structured feedback envelope |
| `ToolCall.swift` | 60 | Parsed tool call |
| `ToolResult.swift` | 40 | Execution result wrapper |
| `Registry/ToolRegistry.swift` | 60 | Actor-based registry |
| `Registry/ToolRegistryProtocol.swift` | 15 | Protocol |
| `Execution/ToolExecutor.swift` | 10 | Protocol |
| `Execution/RealToolExecutor.swift` | 80 | Actual execution |
| `Execution/SandboxDecorator.swift` | 100 | Sandbox + read-before-write |
| `Execution/TelemetryDecorator.swift` | 50 | Timing + logging |
| `Execution/LegacyToolAdapter.swift` | 30 | Bridge from old AITool |
| `Scheduling/SequentialScheduler.swift` | 40 | Sequential batch execution |
| `Feedback/ToolFeedbackFormatter.swift` | 80 | Format + docs generation |
| `Orchestration/CoderOrchestrator.swift` | 120 | Coder mode orchestrator |
| `Guard/ToolLoopGuard.swift` | 100 | Repetition detection |
| `Infrastructure/ToolFileAccessLedger.swift` | 60 | Turn-aware (rewrite) |
| `Infrastructure/PathValidator.swift` | 80 | Move + enhance |
| `Infrastructure/ToolInvocationContext.swift` | 30 | Rewrite |
| `Infrastructure/ToolFileExclusion.swift` | 50 | Move from Core/ |
| `Adapters/ToolFormatAdapter.swift` | 20 | Protocol |
| `Adapters/OpenRouterToolAdapter.swift` | 100 | OpenAI format |
| `Adapters/GemmaToolAdapter.swift` | 80 | Gemma native format |
| `Tools/PatchFileTool.swift` | 150 | NEW: high-performance patches |
| `Execution/WorkerPool.swift` | 120 | Actor worker pool with timeout + memory enforcement |
| `Execution/ResourceGovernor.swift` | 150 | CPU/RAM/disk/network governance |
| `Execution/SpawnedToolExecutor.swift` | 100 | Process-based execution for dangerous tools |

**Total new: ~1,970 lines across 28 files**

### Modified Files

| File | Change |
|------|--------|
| `DependencyContainer.swift` | Add `makeToolingStack()` method + `ResourceGovernor` |
| `ConversationManager.swift` | Route to `CoderOrchestrator` when `useNewArchitecture` is true |
| `ToolScheduler.swift` | Move to `Tooling/Scheduling/` (keep backward-compat alias) |
| `AsyncSemaphore.swift` | Move to `Tooling/Scheduling/` (keep backward-compat alias) |
| `ToolTimeoutCenter.swift` | Integrate with `ResourceGovernor` for timeout enforcement |

### Files to Delete (after cutover)

---

## 14. Tool Migration Plan — Port, Rewrite, or Build

### 14.1 Classification

| Tool | Lines | Quality | Strategy | Phase | Notes |
|------|-------|---------|----------|-------|-------|
| `read_file` | 98 | ⚠️ Fair | **REWRITE** | P1 | Reads entire file. Rewrite with line-range mmap + Data split. |
| `write_file` | 108 | ⚠️ Fair | **REWRITE** | P1 | Needs new feedback + read-before-write. |
| `list_files` | 77 | ✅ Good | PORT | P1 | Simple directory listing. Works. |
| `search_project` | 258 | ✅ Good | **PORT+ENHANCE** | P1 | RAG + FTS5 + symbols. Add tiered search (14.3). |
| `grep` | 94 | ⚠️ Fair | **REWRITE** | P2 | Uses String(contentsOf:). Rewrite with DispatchIO. |
| `replace_in_file` | 125 | ⚠️ Fair | **REWRITE** | P2 | Needs feedback + read-before-write. |
| `delete_file` | 56 | ✅ Good | REWRITE | P2 | Small rewrite for feedback format. |
| `find_file` | 76 | ✅ Good | PORT | P2 | Simple path matching. Works. |
| `get_project_structure` | 89 | ✅ Good | PORT | P2 | Prints directory tree. Works. |
| `index_search_text` | 39 | ✅ Good | PORT | P2 | FTS5 search. Bounded. |
| `index_search_symbols` | 49 | ✅ Good | PORT | P2 | Symbol search. Bounded. |
| `index_find_files` | 50 | ✅ Good | PORT | P2 | Path search. Bounded. |
| `index_list_files` | 47 | ✅ Good | PORT | P2 | Index-backed listing. Works. |
| `index_read_file` | 49 | ✅ Good | PORT+ENHANCE | P2 | Add line-range option. |
| `index_list_memories` | 53 | ✅ Good | PORT | P2 | Simple listing. |
| `index_add_memory` | 49 | ✅ Good | PORT | P2 | Simple add. |
| `terminal_tools` | 644 | ⚠️ Fair | **REWRITE** | P2 | Spawned process. Needs feedback + session mgmt. |
| `patch_file` | NEW | — | **BUILD** | P2 | mmap-based patches (section 22). |
| `web_browse` | 132 | ✅ Good | PORT (spawned) | P3 | Works well. Make spawned process. |
| `web_search` | 39 | ✅ Good | PORT+ENHANCE | P3 | Network semaphore for swarm safety. |
| `GoogleWebSearchEngine` | 221 | ✅ Good | PORT | P3 | Internal. |
| `WebKitSession` | 470 | ✅ Good | PORT (spawned) | P3 | Internal. Move with web_browse. |
| `local_find` | 184 | ❌ Weak | **DEPRECATE** | P3 | Superseded by search_project. |
| `file_tool_write_applier` | 71 | ⚠️ Fair | MERGE | P1 | Merge into WriteFileTool. |
| `file_tool_proposal_stager` | 76 | ❌ Weak | DROP | P1 | "Propose" mode not needed for Coder. |
| `file_tool_param_schema` | 33 | ❌ Weak | DROP | P1 | Replaced by JSONSchema type. |
| `tool_file_access_ledger` | 41 | ✅ | REWRITE | P1 | Turn-aware v2. |
| `tool_invocation_context` | 27 | ❌ Weak | DROP | P1 | Replaced by ExecutionContext. |

### 14.2 Phase Plan

**Phase 1 — Initial (Coder MVP: read, write, search)**

Port: `search_project`, `list_files`
Rewrite: `read_file`, `write_file`, `tool_file_access_ledger`
Build: ToolDefinition, ToolRegistry, ToolFeedback, ToolExecutor chain, SequentialScheduler,
       CoderOrchestrator, WorkerPool, ResourceGovernor, ToolFormatAdapter (OpenRouter),
       ToolFeedbackFormatter
Drop: `file_tool_proposal_stager`, `file_tool_param_schema`, `tool_invocation_context`
Merge: `file_tool_write_applier` into WriteFileTool

→ User can: "find NetworkManager and add error handling" → search → read → write.

**Phase 2 — Mid Range (Coder Complete)**

Port: `find_file`, `get_project_structure`, all 6 index tools
Rewrite: `grep`, `replace_in_file`, `delete_file`, `terminal_tools`
Build: `patch_file`, GemmaToolAdapter, ToolLoopGuard, TelemetryDecorator, SpawnedToolExecutor
Deprecate: `local_find`

→ All daily coding tasks work. Terminal + patches + index search.

**Phase 3 — Mature (Agent Prep)**

Port: `web_browse` (spawned), `web_search`, `WebKitSession`, `GoogleWebSearchEngine`, `WebSessionStore`
Enhance: `search_project` with tiered search (14.3)
Drop: `local_find`

→ Full toolset. Architecture ready for Agent mode.

### 14.3 Tiered Search

Progressive tiers: all indexed, each enriches the previous. Bounded resource usage.

```
Tier 1: File name trie (O(log n), <1ms)      → match by filename/partial path
Tier 2: SQLite FTS5 (1-5ms)                  → full-text content match
Tier 3: Symbol table (5-10ms)                 → language-aware symbol match
Tier 4: Vector embedding (10-50ms)            → semantic similarity
Tier 5: Grep fallback (50-200ms)              → emergency only (index unavailable)
```

Early-exit: if lower tiers have enough high-quality results, skip higher (slower) tiers.

### 14.4 ReadFileTool Rewrite

- `Data.split(separator: 0x0A)` for line scanning (~10μs per MB)
- `pread()` for byte-range reads (no full-file load for line ranges)
- `mmap` for files > 1MB (zero-copy)
- Always returns line-numbered content with byte count
- Swarm-safe: 100 concurrent line-range reads ≈ 1ms total CPU
