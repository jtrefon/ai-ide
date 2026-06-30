# Tool Architecture Research

> **Phase**: Research. Not decision stage. Exploring best options before proposing.
> **Goal**: Design a tool architecture that scales, performs, is testable, and adapts to both small local models and large cloud models.

---

## Table of Contents

1. [Current Architecture Map](#1-current-architecture-map)
2. [What Works Today](#2-what-works-today)
3. [What's Broken or Missing](#3-whats-broken-or-missing)
4. [Architecture Pillars We Need](#4-architecture-pillars-we-need)
5. [Design Dimensions to Explore](#5-design-dimensions-to-explore)
6. [Component Model Exploration](#6-component-model-exploration)
7. [Agentic API (Model-Facing)](#7-agentic-api-model-facing)
8. [Registry & Discovery](#8-registry--discovery)
9. [Prompt System](#9-prompt-system)
10. [Sandbox & Permissions](#10-sandbox--permissions)
11. [Performance & Bare-Metal](#11-performance--bare-metal)
12. [Testing Strategy](#12-testing-strategy)
13. [Migration Path](#13-migration-path)
14. [Open Questions](#14-open-questions)
15. [Parallel Execution & Dependency Mapping (DAG)](#15-parallel-execution--dependency-mapping-dag-scheduling)
16. [LangGraph Removal Analysis](#16-langgraph-removal-analysis)
17. [Sub-Agents & Background Jobs](#17-sub-agents--background-jobs)
18. [Design Patterns — Full Architecture Map](#18-design-patterns--the-full-architecture-map)
19. [What Else to Think About](#19-what-else-should-we-think-about)
20. [Summary: Full Architecture Diagram](#20-summary-what-the-full-architecture-looks-like)
21. [Three-Tier Agent Modes](#21-three-tier-agent-modes)
22. [Patch/Diff Tool](#22-patchdiff-tool--high-performance-line-precise-file-editing)

---

## 1. Current Architecture Map

### Files Currently Involved with Tools (~30 files, ~300 KB)

```
Protocol/Base:
  AITool.swift                    — protocol { name, description, parameters, execute() }
  AIToolCall.swift               — Codable struct for model-generated tool calls
  AIToolProgressReporting.swift  — optional protocol for streaming progress
  AITool+Enhanced.swift          — EnhancedAITool protocol + ToolPromptBuilder

Executor Layer:
  AIToolExecutor.swift            — @MainActor facade
  AIToolExecutor+Batch.swift      — batch scheduling + sequencing
  AIToolExecutor+Execution.swift  — actual execution flow (884 lines!)
  AIToolExecutor+Logging.swift    — error logging

Coordination:
  ConversationToolProvider.swift  — builds tool list per conversation
  LocalModelToolProvider.swift    — filters tools by name for local models
  ToolExecutionCoordinator.swift  — thin wrapper
  ToolLoopHandler.swift           — agent loop (2,775 lines)
  ToolLoopNode.swift              — orchestration graph node
  ToolLoopConstants.swift         — iteration limits
  ToolLoopUtilities.swift         — message building
  ToolCallOrderingSanitizer.swift — message ordering

Infrastructure:
  ToolScheduler.swift             — actor, read/write concurrency
  ToolTimeoutCenter.swift         — singleton, per-call timeout
  ToolArgumentResolver.swift      — argument merging/resolution
  ToolExecutionTelemetry.swift    — singleton, quality metrics
  ToolExecutionLogger.swift       — error logging
  AIToolTraceLogger.swift         — singleton, NDJSON file logger
  PathValidator.swift             — project-root sandboxing
  ToolFileExclusion.swift         — vendor dir exclusion
  ToolInvocationContext.swift     — context extraction from args
  ToolFileAccessLedger.swift      — per-conversation read tracking
  PreWritePreventionEngine.swift  — mutation safety checks

Tool Implementations (25 files):
  ReadFileTool, WriteFileTool, ReplaceInFileTool, DeleteFileTool,
  ListFilesTool, FindFileTool, GrepTool, LocalFindTool,
  SearchProjectTool, GetProjectStructureTool,
  IndexAddMemoryTool, IndexFindFilesTool, IndexListFilesTool,
  IndexListMemoriesTool, IndexReadFileTool, IndexSearchSymbolsTool,
  IndexSearchTextTool,
  GoogleWebSearchTool, WebBrowseTool,
  TerminalTools (RunCommandTool),
  FileToolParameterSchemaBuilder, FileToolProposalStager,
  FileToolWriteApplier, ToolFileAccessLedger, ToolInvocationContext
```

### How Tools Flow Today

```
User types message
  → ConversationSendCoordinator
    → AIInteractionCoordinator calls model
      → Model responds with tool_calls (or not)
        → ToolLoopHandler.handleToolLoopIfNeeded()
          → Checks mode (chat = no tools, agent = all tools)
          → Executes tools via AIToolExecutor.executeBatch()
            → ToolScheduler (read semaphore / write lock)
            → Per-tool: resolve args → validate path → execute → capture result
          → Feeds results back to model (recursive)
          → Repeats until: no tool calls OR max iterations OR repetition detected
```

---

## 2. What Works Today

| Aspect | Assessment |
|--------|-----------|
| **Per-path write locking** | `ToolScheduler` actor with `AsyncLockMap` correctly serializes writes to same file |
| **Read concurrency** | Semaphore cap (default 4) prevents I/O storm |
| **Path sandboxing** | `PathValidator` correctly resolves & enforces project root |
| **Exclusion patterns** | `ToolFileExclusion` mirrors index patterns, skips vendor dirs |
| **Cancel propagation** | `ToolTimeoutCenter` posts notifications + `cancelledToolCallIds` closure pattern works |
| **Mode gating** | `AIMode.allowedTools()` returns either all or none — simple, hard to get wrong |
| **Batch execution** | Sequential-within-batch execution (one tool at a time), results are ordered |
| **Tool call decoding** | `AIToolCall` handles both JSON-string and structured-arguments formats from OpenRouter |
| **Progress streaming** | `AIToolProgressReporting` optional protocol for long-running tools |

---

## 3. What's Broken or Missing

### 3.1 Single Protocol Does Everything

```swift
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get }  // ← raw dictionary
    func execute(arguments: ToolArguments) async throws -> String
}
```

Problems:
- `parameters` is `[String: Any]` — no compile-time safety, no type checking
- No way to declare: read-only vs mutation, scope, timeouts, retry policy
- No way to declare: "this tool needs the index", "this tool needs filesystem"
- No way to declare: "this tool is available in chat mode"
- Execution returns `String` — no structured result, no typed output
- Every tool must manually extract its own arguments with `guard let` casting

### 3.2 Tool Registry Doesn't Exist

Tools are assembled ad-hoc in `ConversationToolProvider.allTools()`:

```swift
tools.append(ReadFileTool(fileSystemService: fileSystemService, pathValidator: pathValidator))
tools.append(ListFilesTool(pathValidator: pathValidator))
// ... 25 lines of manual assembly
```

No central registry means:
- Can't query "which tools need the index?"
- Can't query "which tools are mutations?"
- Can't query "which tools are available in chat mode?"
- Can't discover tools at runtime
- Can't define tool categories/groups
- Local model tool filtering is done by name string matching (`LocalModelToolProvider.safeToolNames`)

### 3.3 Permission/Scope Model is Binary

```swift
case .chat:  return []     // no tools
case .agent: return allTools  // all tools
```

Missing:
- **Read-only agent mode** (can search/read but not write) — not expressible
- **Per-tool scoping** (e.g., "only within src/") — not expressible
- **Network access gating** (web tools on/off) — not expressible
- **Terminal access gating** (run_command on/off) — not expressible
- **Context window budget** (prompt tokens per tool) — not expressible

### 3.4 Two Separate Tool Providers (Local vs Cloud)

`ConversationToolProvider` builds the full set. `LocalModelToolProvider` filters by name.
This is fragile:
- Adding a new tool means adding it to both sets
- No compile-time check that both lists are in sync
- Duplicated knowledge in `safeToolNames` set

### 3.5 Prompt Material is Scattered

`EnhancedAITool` exists but is optional — most tools don't implement it.
The prompt builder (`ToolPromptBuilder`) generates markdown but it's not clear where/when it's used.
Tool descriptions for model prompts are assembled in `ChatPromptBuilder` (1,006 lines) — mixed with other prompt logic.

### 3.6 Execution is @MainActor Bound

`AIToolExecutor` is `@MainActor`. This means:
- Tool execution blocks the main thread for argument resolution
- `ToolTimeoutCenter` updates (`.markProgress`) require main thread hops
- Batch execution (`executeBatch`) creates many `Task { @MainActor in ... }` hops
- The scheduler (`ToolScheduler`) is an actor running on arbitrary threads, but it's called from MainActor context

### 3.7 Testing is Difficult

Singletons used by tools:
- `ToolFileAccessLedger.shared`
- `AIToolTraceLogger.shared`
- `ToolTimeoutCenter.shared`
- `ToolExecutionTelemetry.shared`

Each test needs to either mock these or risk cross-test pollution.
`PathValidator` requires real file system paths.
`ReadFileTool` takes concrete `FileSystemService` — no protocol.

---

## 4. Architecture Pillars We Need

Breaking down the requirements from the task:

| Requirement | Means |
|-------------|-------|
| **Scale** | Add new tools without touching framework code. Runtime discovery. |
| **Performance** | No unnecessary MainActor hops. Direct OS APIs. Low overhead per tool call. |
| **Extensibility** | Plugin-like tool registration. Clear extension points. |
| **Testability** | All dependencies injectable. No singletons in tool execution path. Pure logic extracted. |
| **Model adaptability** | Same tool works for small local and large cloud models. Tool format adapter layer. |
| **Scope & permissions** | Per-tool capability declarations. Mode (chat/agent) enforcement. Path scoping. |
| **Sandbox enclave** | Tools cannot escape project root. Network access is opt-in. Terminal access is opt-in. |
| **Bare-metal / OS APIs** | Use `DispatchIO`, `fcntl`, `sandbox_init`, macOS `OSAllocatedUnfairLock` where appropriate. Avoid foundation abstractions on hot paths. |

---

## 5. Design Dimensions to Explore

These are the main axes we need to make decisions on:

### 5.1 Protocol vs Class Hierarchy

| Option | Pro | Con |
|--------|-----|-----|
| **Protocol-based** (current) | Flexible, tools can be structs, no inheritance tax | Can't share infrastructure, no default implementations for common patterns |
| **Base class** `BaseTool` | Common argument parsing, sandboxing, logging, telemetry | Inheritance coupling, harder to test |
| **Composition + macros** | Tool is a struct with behavior composed via protocols + `@Tool` macro generates boilerplate | Swift macros are new (Swift 6), learning curve |
| **Actor-based tool** | Built-in isolation, no data races | Actor reentrancy may surprise, heavier than struct |

**Key question**: Can we use Swift 6 strict concurrency + macros to get compile-time safety without inheritance?

### 5.2 Schema Definition

| Option | Pro | Con |
|--------|-----|-----|
| **Manual `[String: Any]`** (current) | Simple, flexible | No type safety, runtime errors |
| **`Codable` struct per tool** | Type-safe, testable, auto-JSON schema generation | More boilerplate per tool |
| **`@ToolParameter` macro** | Compile-time annotation → auto schema | Depends on Swift macro maturity |
| **OpenAPI-style JSON Schema builder** | Industry standard, model-native | Verbose, runtime |
| **`@Tool` macro generates both struct + schema** | Single source of truth | Not yet possible (macros can't generate types with conditional logic easily) |

### 5.3 Execution Model

| Option | Pro | Con |
|--------|-----|-----|
| **@MainActor executor** (current) | Direct UI updates | Blocks main thread |
| **Dedicated executor actor** | No main thread blocking | Requires bridging for UI updates |
| **Per-tool actor isolation** | Maximum parallelism, no shared state | Complex lifecycle management |
| **`Task` per tool + cooperative cancellation** | Simple, Swifty | No ordering guarantees |

### 5.4 Model Format Adapter

| Option | Pro | Con |
|--------|-----|-----|
| **Single format** (current) | Simple | OpenRouter format ≠ Gemma format ≠ custom format |
| **Adapter per model family** | Each model gets what it understands | Extra code per model |
| **Middleware format + model adapters** | One internal format, pluggable adapters | More layers |
| **AI-provider-agnostic tool definition** | Tool defines itself once, adapter converts | The adapter is complex |

**Key**: Gemma uses `toolCallFormat: .gemma` (native). OpenRouter uses OpenAI-compatible schema. Local models have limited tool call capacity (max 5 iterations, 128K context).

---

## 6. Component Model Exploration

### 6.1 Proposed Component Map

```
┌─────────────────────────────────────────────────────────────┐
│                    Tool Registry                             │
│  Register · Discover · Query by capability · Query by scope  │
└──────────┬──────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Tool Definition Layer                       │
│  Protocol/Class · Schema · Capabilities · Prompt Material    │
│  Parameters · Validation · Scoping Rules                     │
└──────────┬──────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│                 Execution Engine                             │
│  Scheduler · Concurrency · Timeout · Cancellation · Retry    │
│  Progress Reporting · Telemetry                              │
└──────────┬──────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│               Sandbox & Security Layer                       │
│  Path Validation · Enclave · Network Policy · FS Permissions │
└──────────┬──────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────┐
│               Model Adapter Layer                            │
│  Tool → OpenRouter format · Tool → Gemma format              │
│  Prompt assembly · Schema serialization                      │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Individual Tool Component Model

What a tool definition should contain:

```
ToolDefinition {
  // Identity
  name: String
  displayName: String?
  
  // Schema (model-facing)
  description: String
  parameters: ParameterSchema[]       // typed, not [String: Any]
  
  // Capabilities (for querying/registry)
  requiredCapabilities: [Capability]   // .index, .filesystem, .network, .terminal
  sideEffects: [SideEffect]            // .readsFile, .writesFile, .executesCommand, .networkRequest
  
  // Scoping & Permissions
  allowedModes: [AIMode]               // .chat, .agent, .agentReadOnly
  defaultScope: PathScope?             // .projectRoot, .specificDir("/src")
  sandboxEnclave: SandboxLevel         // .none, .paths, .network, .full
  
  // Prompt material (for model context)
  promptDescription: PromptMaterial    // comprehensive, concise, minimal variants
  
  // Execution Configuration
  defaultTimeout: Duration
  supportsStreaming: Bool
  retryPolicy: RetryPolicy
  
  // Execution
  execute(context: ToolContext) async throws -> ToolResult
}
```

### 6.3 Capabilities System

Rather than filtering tools by name string, we declare capabilities:

```swift
enum ToolCapability: String, Codable {
    // Filesystem
    case fileRead
    case fileWrite
    case fileDelete
    case fileSearch
    case directoryList
    
    // Index
    case indexSearch  // FTS5 + symbol
    case indexSemantic  // vector search
    case indexMemory  // memory CRUD
    
    // Network
    case webSearch
    case webBrowse

    // Terminal
    case commandExecution
    
    // Utility
    case projectStructure
}
```

Then model providers declare what they support:

```swift
// Local model: limited tool set
let localModelCapabilities: Set<ToolCapability> = [
    .fileRead, .fileWrite, .fileDelete, .fileSearch, .directoryList,
    .indexSearch, .indexSemantic, .indexMemory,
    .projectStructure
]

// Cloud model: full set
let cloudModelCapabilities: Set<ToolCapability> = ToolCapability.all
```

The registry answers: "which tools match these capabilities?"

### 6.4 Side Effects System

```swift
enum ToolSideEffect: String, Codable {
    case readsFile
    case writesFile
    case deletesFile
    case modifiesFile  // in-place edit
    case executesCommand
    case makesNetworkRequest
    case readsEnvironment
    case none
}
```

Used for:
- Mode enforcement (chat mode = only `none` + `readsFile`)
- Sandbox policy (network tools get sandboxed differently)
- Repetition detection (mutation tools trigger different guards)
- Audit logging

---

## 7. Agentic API (Model-Facing)

### 7.1 Current Problem

The model sees `AITool` protocoal's surface:
- `name: String`
- `description: String`
- `parameters: [String: Any]` (JSON Schema)

But there's no:
- Standardized format for tool call responses
- Structured error reporting
- Progress/intermediate results format
- Result truncation policy
- Multi-modal result support

### 7.2 Tool Call Format (from model)

Current: `AIToolCall` — Codable, OpenRouter-compatible. Works with OpenRouter, fragile with local models (ad-hoc parsing).

Need: **Unified tool call representation** that any model adapter can produce.

```swift
struct ToolCall: Sendable {
    let id: String
    let toolName: String
    let arguments: [String: ToolValue]  // typed, not [String: Any]
}

enum ToolValue: Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case array([ToolValue])
    case dictionary([String: ToolValue])
}
```

### 7.3 Tool Feedback Framework (CRITICAL)

**This is the single most important design decision for agent reliability.**

Every tool returns a **consistent, structured feedback envelope**. The model must know exactly what to expect — no ambiguous strings, no guesswork. This is documented in the system prompt so the model "feels at home" with every tool.

```swift
/// Every tool returns this. Never a raw String.
/// The model adapter serializes this to the model's preferred format,
/// but the internal structure is always the same across all tools.
struct ToolFeedback: Sendable, Codable {
    /// What happened
    let status: ToolFeedbackStatus
    
    /// Human-readable summary (1-2 lines)
    /// Success: "Created file src/main.swift (245 bytes, 42 lines)"
    /// Error:   "Cannot delete file: resource busy by process PID 1234"
    let message: String
    
    /// Structured payload for query tools (search, read, list)
    /// nil for command tools (write, delete) that just succeed/fail
    let content: ToolContent?
    
    /// Error details + recovery alternatives
    /// nil on success
    let error: ToolErrorInfo?
}

// ======= STATUS =======

enum ToolFeedbackStatus: String, Sendable, Codable {
    /// Tool completed as expected
    case success
    /// Tool failed
    case error
    /// Partial (3/5 files written, 2 failed)
    case partial
}

// ======= CONTENT (for query/read tools: search, list, read) =======

struct ToolContent: Sendable, Codable {
    /// The actual result data
    let data: ToolContentData
    /// Metadata for model awareness
    let metadata: [String: String]?
}

enum ToolContentData: Sendable, Codable {
    case text(String)                           // file content, grep output
    case json([String: AnyCodable])             // structured data
    case items([ToolContentItem])               // lists (files, symbols, matches)
    case binary(Data, mimeType: String)
    case empty
}

struct ToolContentItem: Sendable, Codable {
    let label: String           // "NetworkManager"
    let description: String?    // "class for managing network connections"
    let path: String?           // "src/network/NetworkManager.swift"
    let lineNumber: Int?        // 1
    let kind: String?           // "class", "protocol", "file", "match"
}

// ======= ERROR (detailed + recovery alternatives) =======

struct ToolErrorInfo: Sendable, Codable {
    /// Machine-readable error code
    /// Examples: FILE_NOT_FOUND, PERMISSION_DENIED, RESOURCE_BUSY,
    ///          PATH_OUTSIDE_SANDBOX, FILE_ALREADY_EXISTS, INVALID_ARGUMENT,
    ///          NETWORK_TIMEOUT, COMMAND_FAILED, LOCK_CONTENTION, NOT_INSTALLED
    let code: String
    
    /// Human-readable description
    let message: String
    
    /// Can the agent retry with different arguments?
    /// true  → agent should attempt recovery (try different path)
    /// false → agent should stop trying (FS is read-only)
    let recoverable: Bool
    
    /// Alternative approaches the model can try instead
    /// Each alternative suggests a different tool or approach
    let alternatives: [ToolAlternative]?
}

struct ToolAlternative: Sendable, Codable {
    /// What this alternative does
    let description: String     // "Use the terminal to force-remove the file"
    
    /// Suggested invocation the model can make
    let suggestion: String      // "rm -f src/config.lock"
    
    /// Tool name if using a different tool
    let toolName: String?       // "run_command"
    
    /// Pre-built arguments for the alternative tool
    let arguments: [String: String]?
}
```

#### Feedback Examples (what the model sees in context)

**Command tool** (success):
```
status: success
message: "Created file src/NetworkManager.swift (245 bytes, 42 lines)"
content: null
error: null
```

**Command tool** (error with alternatives — the agent can immediately recover):
```
status: error
message: "Cannot delete file src/config.lock: resource busy by process PID 9876"
error:
  code: RESOURCE_BUSY
  recoverable: true
  alternatives:
    - description: "Force-delete using terminal command"
      suggestion: "rm -f src/config.lock"
      toolName: "run_command"
      arguments:
        command: "rm -f src/config.lock"
```

**Query tool** (success with structured content):
```
status: success
message: "Found 3 symbol matches for 'NetworkManager'"
content:
  data:
    items:
      - label: "NetworkManager"
        kind: "class"
        path: "src/network/NetworkManager.swift"
        lineNumber: 1
      - label: "NetworkManagerDelegate"
        kind: "protocol"
        path: "src/network/NetworkManager.swift"
        lineNumber: 87
      - label: "networkManager"
        kind: "variable"
        path: "src/AppDelegate.swift"
        lineNumber: 14
  metadata:
    totalResults: "3"
    queryTimeMs: "12"
error: null
```

**Query tool** (error — model should notice its own mistake):
```
status: error
message: "No results found for 'NetwrkManager'"
error:
  code: NO_MATCHES
  recoverable: true
  alternatives:
    - description: "Retry with corrected spelling"
      suggestion: "NetworkManager"
      toolName: "search_project"
      arguments:
        query: "NetworkManager"
    - description: "Use fuzzy search"
      suggestion: "Netwrk"
      toolName: "grep"
      arguments:
        pattern: "Netwrk"
        path: "."
```

#### Why This Framework is Non-Negotiable

| Without Framework | With Framework |
|------------------|----------------|
| `delete_file` fails → "Error: file is busy" → agent retries same call → same error → agent drops out | `delete_file` fails → `RESOURCE_BUSY` + `alternatives: [rm -f]` → agent immediately recovers using terminal |
| `search_project` returns "No results" → agent assumes code doesn't exist, builds from scratch | `search_project` returns `NO_MATCHES` + `alternatives: [grep "Netwrk"]` → agent notices typo, retries, finds existing code |
| Terminal command fails → "Exit code 127" → agent has no idea what 127 means | Terminal command fails → `COMMAND_NOT_FOUND: 'gcc'` + `alternatives: [install via brew, use clang]` → agent recovers |
| `write_file` overwrites existing → "Success" → agent silently clobbered user's work | `write_file` overwrites → "Created file (overwrote existing, 245 bytes)" → agent is aware and can report to user |

#### System Prompt Documentation (tool feedback contract)

Every tool's `PromptMaterial` includes a **feedback specification** so the model knows the exact format:

```swift
struct PromptMaterial: Sendable {
    // ... existing fields ...
    
    /// Expected feedback format (documented in system prompt)
    let feedbackFormat: FeedbackDocumentation
    
    /// Error codes the model should handle
    let errorCodes: [ErrorCodeDocumentation]
    
    /// Fallback chain: what to try when this tool fails
    let fallbackChain: [FallbackTool]
}

struct FeedbackDocumentation: Sendable {
    let statusValues: [String]          // "success, error, partial"
    let contentFormats: [String]        // "text, json, items, binary"
    let example: String                 // Concrete example the model can reference
}

struct ErrorCodeDocumentation: Sendable {
    let code: String                    // "RESOURCE_BUSY"
    let meaning: String                 // "File locked by another process"
    let recommendedAction: String       // "Try run_command with rm -f"
    let alternativeTool: String?        // "run_command"
}

struct FallbackTool: Sendable {
    let condition: String               // "when write_file fails with FILE_ALREADY_EXISTS"
    let tryTool: String                 // "replace_in_file"
    let withArguments: [String: String]?
}
```

The system prompt includes a section like:
```
## Tool Feedback Format

All tools return feedback in this structure:

status: [success | error | partial]
message: Human-readable summary
content: Present for query tools (search, read, list). Null for command tools.
error: Present on failure. Contains error code, alternatives to try.

When a tool fails, check error.alternatives for suggested recovery paths.
Do NOT retry the same call with the same arguments.
```

### 7.4 Format Adapter Interface

```swift
protocol ToolFormatAdapter: Sendable {
    /// Convert internal tool definitions to model-specific JSON schema
    func encodeSchema(_ tool: ToolDefinition) -> [String: Any]
    
    /// Convert model response into internal ToolCall
    func decodeCall(from json: [String: Any]) throws -> ToolCall
    
    /// Convert internal ToolResult into model-specific response text
    func encodeResult(_ result: ToolResult) -> String
}
```

Built-in adapters:
- `OpenRouterToolAdapter` — OpenAI-compatible `tools` array + `tool_calls`
- `GemmaToolAdapter` — Gemma 4 E4B native format (tool call format: `.gemma`)
- `MCPToolAdapter` — future: Model Context Protocol

---

## 8. Registry & Discovery

### 8.1 What a Registry Should Do

```swift
protocol ToolRegistry: Sendable {
    /// Register a tool at startup (or at runtime for plugins)
    func register(_ tool: ToolDefinition)
    
    /// Query tools by capability
    func tools(capabilities: Set<ToolCapability>) -> [ToolDefinition]
    
    /// Query tools by mode
    func tools(for mode: AIMode) -> [ToolDefinition]
    
    /// Query a specific tool by name
    func tool(named: String) -> ToolDefinition?
    
    /// All registered tools
    var allTools: [ToolDefinition] { get }
    
    /// Tool counts by category
    var summary: RegistrySummary { get }
}
```

### 8.2 Registration Approach

**Option A: Explicit manual registration**
```swift
registry.register(ReadFileTool.definition)
registry.register(WriteFileTool.definition)
// ...
```
Pro: Simple, explicit. Con: Easy to forget.

**Option B: Auto-discovery via `@Tool` macro**
```swift
@Tool
struct MyNewTool {
    static let name = "my_tool"
    static let capabilities: Set<ToolCapability> = [.fileRead]
    // macro generates `.definition` and registration
}
```
Pro: Single source of truth. Con: Macro limitations.

**Option C: Plugin bundle scanning**
```swift
registry.scan(bundle: .main)
registry.scan(bundle: .plugin("/path/to/MyTool.bundle"))
```
Pro: True extensibility. Con: Over-engineered for v1.

**Recommendation (to research)**: Start with Option A (explicit), design the macro `@Tool` annotation for v2.

### 8.3 Registry Queries for Model Selection

```swift
// Local model gets curated subset
let localTools = registry.tools(capabilities: localModelCapabilities)

// Cloud model gets everything except dangerous operations
let cloudTools = registry.tools(for: .agent)
    .filter { $0.sandboxEnclave != .full }

// Chat mode gets read-only
let chatTools = registry.tools(capabilities: [.fileRead, .indexSearch, .indexSemantic])
```

---

## 9. Prompt System

### 9.1 Current State

- `AITool+Enhanced.swift` defines `EnhancedAITool` with 10 string properties
- `ToolPromptBuilder` assembles markdown from these
- But: most tools don't implement `EnhancedAITool`
- The prompt builder output is markdown text mixed into `ChatPromptBuilder` (1,006 lines)

### 9.2 Proposed Approach

Each tool carries **multiple prompt variants**:

```swift
struct PromptMaterial: Sendable {
    /// Short description (1-2 lines) — for small models / context budget
    let concise: String
    
    /// Standard description with parameters — default
    let standard: String
    
    /// Full documentation with examples — for large cloud models
    let comprehensive: String
    
    /// Success/error indicators for the model to self-evaluate
    let successCriteria: String?
    let errorPatterns: String?
    
    /// When to use / when NOT to use
    let guidance: ToolGuidance?
}
```

The prompt assembler selects the right variant based on:
- Model type (local = concise, cloud = comprehensive)
- Available context window
- Whether the tool has been used before

### 9.3 Prompt Assembly Pipeline

```
User request
  → Determine model type (local/cloud)
  → Query registry for available tools (filtered by capabilities/permissions)
  → For each tool, select prompt variant (concise/standard/comprehensive)
  → Assemble "## Available Tools" section
  → Inject into system prompt
```

This logic moves OUT of `ChatPromptBuilder` (1,006 lines) into a dedicated `ToolPromptAssembler`.

---

## 10. Sandbox & Permissions

### 10.1 Current Sandbox

`PathValidator` ensures all file paths resolve within `projectRoot`. This is opt-in — each tool must call it. Some tools (terminal, web) completely bypass it.

### 10.2 Proposed Multi-Layer Sandbox

```
Layer 1: Filesystem Enclave
  - All file tools MUST resolve paths through PathValidator
  - Additional: restrict by path patterns (allowlist: ["src/**"], blocklist: [".git/**", "node_modules/**"])
  - PathValidator becomes non-optional infrastructure (enforced by base class / executor)

Layer 2: Network Enclave
  - Web tools check against allowlist of domains
  - No arbitrary network access
  - configurable: "allow all", "allow documented", "block"

Layer 3: Terminal Enclave
  - Command execution sandboxed to project directory
  - Read-only commands allowed in chat mode
  - Audit log of all commands

Layer 4: Mode Enforcement
  - Chat mode: only tools with sideEffects ⊆ [.none, .readsFile]
  - Agent Read-Only mode: only tools with sideEffects ⊆ [.readsFile, .readsIndex, .networkRequest]
  - Agent mode: all tools
```

### 10.3 Enclave Configuration

Rather than each tool deciding its scope, the executor applies enclave rules:

```swift
struct SandboxConfiguration: Sendable {
    var projectRoot: URL
    var allowedPathPatterns: [GlobPattern]  // default: ["**"]
    var blockedPathPatterns: [GlobPattern] // default: [".git/**", "node_modules/**"]
    var allowedDomains: [String]?          // nil = block all network, ["*"] = allow all
    var allowTerminal: Bool = false
    var allowTerminalReadOnly: Bool = true
}
```

---

## 11. Performance & Bare-Metal

### 11.1 Current Performance Issues

- `@MainActor` executor blocks the UI thread during tool argument resolution
- `ToolTimeoutCenter` uses a `Timer.publish(every: 0.2)` on MainActor — 5 times/second even when idle
- Tools use Foundation `String(contentsOf:)` for file reads — no mmap, no dispatch I/O
- `Task { await readSemaphore.signal() }` in `defer` creates unnecessary task creation per tool
- Tool execution logs go through `AIToolTraceLogger.shared` which does JSON serialization + file I/O synchronously on the caller's thread

### 11.2 Bare-Metal Opportunities

| Area | Current | Potential |
|------|---------|-----------|
| **File reading** | `String(contentsOf: utf8)` | `mmap()` + `dispatch_data_create` |
| **Large file reading** | Full file into memory | `DispatchIO` chunked reading |
| **Concurrency control** | Actor `AsyncSemaphore` | `os_unfair_lock` + `dispatch_semaphore_t` for hot path |
| **Logging** | JSON serialization + FileHandle | `OSLog` with structured logging |
| **Timeouts** | Timer on MainActor | `DispatchSourceTimer` on dedicated queue |
| **Argument parsing** | `[String: Any]` casting | `Codable` structs (compile-time) |
| **Progress callbacks** | `@MainActor @Sendable` closure | `OSAllocatedUnfairLock` accumulator + batch update |
| **Memory pressure** | Wrapped in model service | `dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, ...)` |
| **File watching** | (external) | `FSEvents` or `kqueue` directly |

### 11.3 Performance Target

Hot path (tool execution, measured from model response → tool result):
| Tool Type | Current | Target |
|-----------|---------|--------|
| `read_file` (100-line file) | ~2ms | <0.5ms |
| `grep` (1000 files) | ~50ms | <10ms (with indexing) |
| `write_file` (small) | ~1ms | <0.3ms |
| Tool dispatch overhead | ~0.5ms | <0.1ms |

Implementation principles:
1. No main thread hops on the tool execution path (use `Sendable` + actor isolation)
2. No Foundation `String` APIs on large files (use `Data` + encoding on demand)
3. No per-tool-call Task creation overhead (reuse task pools or continuation)
4. No serialization overhead on hot path (keep structured data as structs, serialize only at model boundary)

---

## 12. Testing Strategy

### 12.1 What Makes Tools Hard to Test Today

- `ReadFileTool` takes concrete `FileSystemService` — can't mock
- `WriteFileTool` depends on `FileToolWriteApplier` and `FileToolProposalStager` — both use real file system
- `ToolFileAccessLedger.shared` — singleton, state leaks between tests
- `PathValidator` needs real paths
- `AIToolExecutor` is `@MainActor` — tests must run on main thread
- `ToolTimeoutCenter.shared` — timer runs in background

### 12.2 Proposed Test Infrastructure

**Protocols for dependency inversion** (already partially done, needs to go all the way):

```swift
protocol FileSystemReader: Sendable {
    func readFile(at url: URL) async throws -> Data
    func fileExists(at url: URL) -> Bool
}

protocol FileSystemWriter: Sendable {
    func writeFile(data: Data, to url: URL) async throws
    func deleteFile(at url: URL) async throws
}
```

**In-memory implementations for tests**:
```swift
final class InMemoryFileSystem: FileSystemReader, FileSystemWriter {
    private var files: [String: Data] = [:]
    // ...
}
```

**Testable components**:
- `ToolDefinition` is a pure value type — test schema generation
- `ToolPromptAssembler` takes `[ToolDefinition]` → String — pure function
- `PathValidator` takes `projectRoot` URL — test with temp directory
- Each tool's `execute()` takes context + dependencies — test with in-memory impls
- `ToolScheduler` is an actor — test with controlled concurrency
- `ToolRegistry` is a value type — test query logic

### 12.3 Test Pyramid

```
     ╱╲
    ╱  ╲         2-3 Integration tests (end-to-end: tool call → response)
   ╱    ╲
  ╱      ╲       5-10 Scheduler + executor tests (concurrency, timeouts, cancellation)
 ╱        ╲
╱──────────╲      1 test per tool (25+) + 1 test per infrastructure component = 40+ unit tests
```

---

## 13. Migration Path

### 13.1 Strategy: Parallel Architecture, Gradual Migration

```
Phase 0 ─ Research & Design (we are here)
         Define protocols, registry interface, sandbox model, adapter interface.
         
Phase 1 ─ Core Infrastructure (parallel, non-breaking)
         Build new ToolRegistry, ToolDefinition, ToolCapabilities, ToolSideEffects
         Build InMemoryFileSystem + test helpers
         Build ToolPromptAssembler
         Build new SandboxConfiguration + PathValidator v2
         All current tools continue to work untouched.
         
Phase 2 ─ First Tools Migrated
         Port 2-3 tools to new architecture:
         - ReadFileTool → new definition + capabilities + test
         - WriteFileTool → new definition + capabilities + test
         - GrepTool → new definition + capabilities + test
         Both old and new registries exist side by side.
         
Phase 3 ─ Model Adapters
         Build OpenRouterToolAdapter + GemmaToolAdapter
         New tools use new schema; old tools can be wrapped in adapters.
         
Phase 4 ─ Cutover
         Make new ToolRegistry the primary source.
         Route all tool queries through new path.
         Remove old ConversationToolProvider, LocalModelToolProvider.
         Remove AITool+Enhanced.swift (replaced by prompt material on definition).
         
Phase 5 ─ Cleanup
         Delete old protocol cruft.
         Extract ToolLoopHandler repetition detection into ToolLoopGuard.
         Reduce ToolLoopHandler from 2775 → ~300 lines (orchestrator only).
```

### 13.2 Coexistence Strategy

```swift
// New registry
let newRegistry = ToolRegistry()
// Old collection
let oldTools = ConversationToolProvider(...).allTools(...)

// Decision: which set to use?
if newRegistry.hasTool(named: toolCall.name) {
    // Execute through new path
    let result = try await newRegistry.execute(toolCall, context: ctx)
} else {
    // Fall back to old path
    let result = try await oldExecutor.execute(toolCall)
}
```

This lets us migrate one tool at a time without breaking existing functionality.

---

## 14. Open Questions

These need exploration before the decision stage:

1. **Macro vs manual**: Can Swift 6 `@Tool` macros generate schema + registry boilerplate reliably? What are the limitations (conditional parameters, generic schemas)?

2. **Actor isolation**: Should individual tools be actors, or should the executor be an actor that calls Sendable struct tools? Actors protect state but prevent reentrancy. Struct tools require all dependencies to be injected.

3. **Schema generation**: Best approach for generating JSON Schema from Swift types? Options: `Codable` + reflection, `@ToolParameter` macro, manual dictionary, JSON Schema builder DSL.

4. **Retry & recovery policy**: Should retry be defined per-tool or by the executor? For example, `write_file` should retry on lock contention but not on path validation failure. Where does this logic live?

5. **Cancellation granularity**: Per-tool-call cancellation works. Should we support per-tool-call-iteration cancellation (long-running tools like terminal commands)?

6. **Tool chaining**: Should tools be able to call other tools? (e.g., `search_project` calling `read_file` to show snippets). This adds complexity but enables powerful composition.

7. **Plugin loading**: Should external tools be loadable at runtime via `NSBundle` / `@_exported`? This affects the registry design (mutable, thread-safe registry vs. frozen-at-startup).

8. **Telemetry architecture**: Current singletons (ToolExecutionTelemetry, AIToolTraceLogger) are convenient but untestable. Replace with injected `ToolTelemetry` protocol that has `.noop` implementation for tests?

9. **Context window budget**: Can we estimate tool prompt cost (in tokens) per tool so the prompt assembler can make intelligent decisions about which tools to include when context is tight?

10. **LLM tool call format divergence**: OpenRouter is evolving toward Anthropic-style tool use. Gemini has its own format. MCP is emerging. How extensible do adapters need to be?

---

## 15. Parallel Execution & Dependency Mapping (DAG Scheduling)

### 15.1 Current State: Sequential Batch Execution

Today `executeBatch()` runs tools one-at-a-time in a flat array. The `ToolScheduler` has read concurrency (semaphore of 4) and per-path write locking, but the **batch ordering is sequential** — each tool call waits for the previous one to finish:

```swift
// Current: sequential
for task in tasks {
    let message = await task.value
    results.append(message)
}
```

This is safe but slow. If the model issues 5 independent read calls, they run serially.

### 15.2 What Parallel Execution Unlocks

| Scenario | Sequential | Parallel (DAG) |
|----------|-----------|----------------|
| Read 5 unrelated files | 5 × file read latency | 1 × file read latency |
| `search_project` + read top result | 2 sequential rounds | 1 round (if read depends on search) |
| Write 3 files to different paths | 3 serial writes | 3 parallel writes |
| Web search + file read simultaneously | 5s+ total | 2s total (network I/O overlaps FS I/O) |

### 15.3 Dependency Mapping: Tool Calls as a DAG

The model's tool calls form a **Directed Acyclic Graph**:

```swift
struct ToolCallNode: Sendable {
    let id: String
    let toolName: String
    let arguments: ToolArguments
    let dependencies: [String]  // IDs of tool calls that must complete first
    
    // Result placeholders (filled by executor)
    var status: ToolExecutionStatus = .pending
    var result: ToolResult?
}
```

**How the model declares dependencies**:
The model doesn't explicitly declare a DAG. The executor **infers** it from the tool calls + their arguments + declared side effects:

```swift
// Model issues 3 tool calls:
// 1. search_project("NetworkManager")  → reads index, no file deps
// 2. read_file("src/NetworkManager.swift")  → reads a file, depends on search to find the path
// 3. read_file("src/Utils.swift")  → reads a file, no deps

// Infer dependencies:
// - call_2 depends on call_1? Only if call_2's path argument contains "{call_1.result}"
// - call_3 depends on nothing
// - call_1 depends on nothing
// Result: call_1 ∥ call_3 (parallel), then call_2 (sequential after call_1)
```

**Explicit dependency annotation** (alternative / complement):
Tools can declare that their execution depends on another call's output:

```json
{
  "tool_calls": [
    { "id": "call_1", "name": "search_project", "arguments": {"query": "class NetworkManager"} },
    { "id": "call_2", "name": "read_file", "arguments": {"path": "$ref:call_1.top_result.path"} },
    { "id": "call_3", "name": "read_file", "arguments": {"path": "src/Utils.swift"} }
  ]
}
```

The `$ref:` syntax tells the executor: "this argument depends on call_1's output". The executor **resolves** `$ref:` placeholders after the dependency completes, then schedules the dependent tool.

### 15.4 DAG Scheduler Design

```swift
actor DAGScheduler {
    private let configuration: Configuration
    
    struct Configuration: Sendable {
        var maxConcurrentTasks: Int  // default: CPU core count
        var enableDependencyResolution: Bool  // default: true
        var enableResultInjection: Bool  // inject $ref values into arguments
    }
    
    func schedule(
        toolCalls: [AIToolCall],
        availableTools: [ToolDefinition],
        sandbox: SandboxConfiguration,
        context: ExecutionContext
    ) async -> [ToolResult] {
        // 1. Parse calls into nodes, infer dependencies
        let graph = try await DependencyGraph.build(from: toolCalls, tools: availableTools)
        
        // 2. Validate graph (no cycles, all deps resolvable)
        try graph.validate()
        
        // 3. Topological sort + parallel scheduling
        return try await executeGraph(graph, context: context)
    }
    
    private func executeGraph(
        _ graph: DependencyGraph,
        context: ExecutionContext
    ) async throws -> [ToolResult] {
        // Standard DAG execution:
        // - Track in-degree for each node
        // - Nodes with in-degree 0 run immediately in parallel (via task group)
        // - When a node completes, decrement in-degree of dependents
        // - When a dependent's in-degree hits 0, schedule it
        // - Collect all results, maintain original call order in final array
    }
}
```

### 15.5 Dependency Inference Rules

The executor infers dependencies from the intersection of:
1. **File paths** — call_2's path matches call_1's output path → dependency
2. **Argument references** — explicit `$ref:` syntax → dependency
3. **Tool side effects** — `write_file` after `read_file` on same path → implicit dependency (for correctness, not read-after-write race)
4. **Conversation ordering** — model typically issues them in logical order already

```
Rule matrix:

                    call_B reads file_X    call_B writes file_X    call_B is network
call_A reads file_X    NO (both read)         YES (read→write)       NO
call_A writes file_X    YES (write→read)      YES (same path)        NO
call_A is network       NO                    NO                      NO
```

### 15.6 Design Patterns Applied

| Pattern | Where |
|---------|-------|
| **DAG / Topological Sort** | Core scheduling algorithm |
| **Task Group** (`withThrowingTaskGroup`) | Swift concurrency primitive for parallel execution |
| **Dependency Injection** | `DependencyGraph.build(from:tools:)` takes tools from registry |
| **Observer** | Progress callbacks per task completion |
| **Builder** | `DependencyGraph` is built by `DependencyGraphBuilder` with validation steps |

### 15.7 Complexity & Risks

| Risk | Mitigation |
|------|-----------|
| Model outputs cyclical tool calls | Validate DAG before execution, reject cycles |
| Too many parallel file reads flood I/O | `maxConcurrentTasks` cap (default: CPU count) |
| `$ref` resolution fails (wrong path) | If ref can't resolve, run with original args (graceful fallback) |
| Debugging parallel flow is harder | Structured logging with `traceId` per DAG execution |
| Tool result ordering matters for conversation | Final array preserves original `toolCalls` order |

### 15.8 When NOT to Parallelize

Some tool categories must stay sequential:
- `replace_in_file` then `read_file` on same file (read-after-write verification)
- Terminal commands in the same session
- Web browsing in the same session (stateful session)
- Any tool annotated `@Sequential` or with sideEffect `.modifiesState`

The `ToolDefinition` includes `isolation: ToolIsolation`:

```swift
enum ToolIsolation: Sendable {
    case concurrent        // safe to run in parallel
    case pathIsolated      // parallel with other tools on different paths
    case sessionIsolated   // sequential within session (terminal, web)
    case globallySerial    // never runs in parallel (DB migrations, etc.)
}
```

---

## 16. LangGraph Removal Analysis

### 16.1 What Was There Before

The codebase previously used an external graph framework (LangGraph-style) for agent orchestration. It was removed in the refocus effort (Phase 1 & 3), replaced with the custom `OrchestrationGraph`.

### 16.2 What the Current Orchestration Looks Like

Today's `OrchestrationGraph` is a **linear state machine disguised as a graph**:

```
StrategicPlanning → TacticalPlanning → Dispatcher → ToolLoop
  → EmptyResponseRecovery → BranchReview → FinalResponse
                                    ↓ (if QA enabled)
                              QAToolOutputReview → QAQualityReview
```

Key characteristics:
- **Sequential** — one node runs, returns next node id, repeat
- **No parallelism** — each node is a discrete step (planner → dispatcher → tool loop → reviewer)
- **No persistence** — state lives in memory, lost on crash
- **No pause/resume** — the `maxTransitions` cap (64) is a hard stop, not a pause
- **No branching** — BranchReview is a conditional (choose between two paths), not a fan-out
- **All on `@MainActor`** — the runner blocks the main thread for the entire workflow duration

### 16.3 Was the Removal a Good Idea?

**Short answer: Yes for the local model, premature for the cloud model.**

The removal was motivated by two things:
1. The external framework was Python-based (LangChain/Python), couldn't run natively in Swift
2. The local model doesn't need orchestration (it's a direct LLM call — see Phase 1.2)

**For the local model path**: Correct decision. No orchestration means lower latency, simpler code, fewer failure modes. The local model runs a stripped-down path (direct LLM call → tool loop → done).

**For the cloud model path**: The removal was correct in *eliminating an external dependency that didn't belong in a Swift app*, but the *replacement* is too thin. The custom `OrchestrationGraph` is a linked list — it doesn't provide:
- Parallel sub-graphs
- Persistent state (pause/resume)
- Long-running agent sessions
- Sub-agent delegation
- Event-driven execution (wake on file change)
- Conditional fan-out (try 3 approaches in parallel, pick the first that succeeds)

### 16.4 What We Should Build (Not Import)

Do NOT try to import LangGraph (Python) or any external graph framework. Instead, leverage **Swift's structured concurrency** which already provides the primitives:

| LangGraph Concept | Swift Equivalent |
|-------------------|------------------|
| Graph node | `OrchestrationNode` protocol (keep, extend) |
| State passing | `OrchestrationState` (keep, make persistent) |
| Parallel branches | `async let` / `withThrowingTaskGroup` |
| Conditional edges | `switch` on state signals (already works) |
| Sub-graphs | Nested `OrchestrationGraph` instances |
| Checkpoint/persist | Codable state → SQLite or file |
| Human-in-the-loop | `AsyncStream` + continuation (wait for user input) |
| Long-running agent | `Task` with `AsyncStream` for progress |

**Recommendation**: Evolve `OrchestrationGraph` from a linear chain into a **true DAG** using Swift's structured concurrency. Keep the protocol, change the runner.

### 16.5 DAG-Based Orchestration Runner (Next Gen)

```swift
actor DAGOrchestrationRunner {
    private let graph: OrchestrationGraph
    
    func run(initialState: OrchestrationState) -> AsyncStream<OrchestrationEvent> {
        // Returns a stream of events so the UI can react
        // States: running, nodeCompleted(named, duration), paused, failed, completed
        AsyncStream { continuation in
            Task {
                // Topological traversal through graph
                // Support fan-out: run independent nodes in parallel
                // Support fan-in: wait for all dependencies before proceeding
                // Support persistence: checkpoint state after each node
            }
        }
    }
}
```

---

## 17. Sub-Agents & Background Jobs

### 17.1 The Gap Today

The agent runs **synchronously in the foreground**. When the user sends a message:
1. The entire UI freezes (via `@MainActor` orchestration runner)
2. The model thinks, plans, calls tools, loops — user watches and waits
3. No work can happen while the user edits
4. No way to say "keep working on this, I'll check back"

### 17.2 Background Job Model

```swift
/// A background job spawned by the agent. Runs independently of the conversation.
/// Returns progress updates and a final result.
struct BackgroundJob {
    let id: String
    let description: String        // "Refactoring NetworkManager..."
    let createdAt: Date
    let status: JobStatus
    
    /// Jobs can produce periodic progress snapshots
    let progressStream: AsyncStream<JobProgress>
    
    /// Jobs can request user input mid-execution (human-in-the-loop)
    let userInputRequests: AsyncStream<UserInputRequest>
}

enum JobStatus: String, Sendable {
    case running
    case paused
    case awaitingInput   // waiting for user to answer a question
    case completed
    case failed(error: String)
    case cancelled
}

struct JobProgress: Sendable {
    let message: String             // "Searching for references to connect()..."
    let percentComplete: Double?    // 0.0 ... 1.0, nil if unknown
    let intermediateResults: [ToolResult]?
}
```

**How the agent spawns a sub-agent**:

The agent gets a new tool: `spawn_sub_agent`:

```swift
{
  "name": "spawn_sub_agent",
  "description": "Spawn a background sub-agent to work on a task independently.",
  "parameters": {
    "task": "Review all files in src/network/ for thread safety issues",
    "context": "We're refactoring the networking layer to use Swift actors",
    "model": "cheapest_available",  // optional: default, cheap, thorough
    "notify_on": "completion"       // optional: on_completion, on_progress, never
  }
}
```

The sub-agent runs **as a separate task** with its own:
- Conversation context (scoped to the sub-task)
- Tool access (potentially restricted — read-only review vs. mutation)
- Progress stream (periodic "here's what I found so far")
- Lifespan (can outlive the parent conversation turn)

### 17.3 Human-in-the-Loop (Pause & Ask)

Long-running background jobs often need user decisions:

```swift
struct UserInputRequest: Sendable {
    let id: String
    let question: String           // "I found 3 approaches to fix this. Which should I use?"
    let options: [String]?         // ["Option A: ...", "Option B: ...", "Option C: ..."]
    let context: String?           // Supporting info for the decision
    let respondsTo: String?        // The tool call ID this input is for
    
    /// The user's response, provided asynchronously
    var response: UserInputResponse
}

struct UserInputResponse: Sendable {
    let choice: String
    let explanation: String?       // "Option B — it's the most maintainable"
    let additionalNotes: String?
}
```

The background job **pauses** when it needs input. The UI shows a notification: "The agent has a question for you". The user answers when ready. The job resumes.

### 17.4 Periodic Async Updates

While a background job runs, it pushes updates:

```swift
// Job publishes progress via AsyncStream
for await progress in job.progressStream {
    updateUI(with: progress)
    // User sees: "🔍 Searching for references to connect()..."
    // Later: "📝 Found 12 references in 8 files"
    // Later: "✅ Review complete — 3 thread safety issues found"
}
```

The UI shows a **side panel** for active background jobs:
- Job list with status badges
- Expandable progress per job
- "Stop" button per job
- "View Results" when complete

### 17.5 Checkpoint & Resume (Git-Native)

**Decision: No custom checkpoint store. Git is the checkpoint system.**

We do not build a custom `JobCheckpointStore`. Git already provides:
- **Snapshots**: every commit is a point-in-time snapshot
- **Rollback**: `git reset` / `git revert` to undo changes
- **Branching**: each sub-agent or background job works on its own branch
- **Diffing**: `git diff` shows exactly what changed
- **Safety**: commits before every task boundary guarantee recoverability

#### Workflow

```
1. Agent session starts → create branch: agent/session-<id>
2. Before each significant operation → git add + git commit
   - "feat(agent): pre-task checkpoint - analyzing NetworkManager"
   - "feat(agent): pre-mutation checkpoint - about to refactor"
3. On tool failure / agent confusion → git reset --hard HEAD~1
   (undoes the failed operation, agent retries from clean state)
4. On user cancel → git reset --hard agent-session-start
   (back to where the session began, no trace left)
5. On success → squash-merge branch into main
   (clean history, one commit per agent task)
```

#### Sub-Agent Branch Strategy

```
main
 └── agent/session-abc123/          ← orchestrator's branch
      ├── sub-task-1/               ← sub-agent 1's independent branch
      ├── sub-task-2/               ← sub-agent 2's independent branch
      └── sub-task-3/               ← sub-agent 3's independent branch
```

Each sub-agent works on its own branch, isolated from others. When a sub-agent completes, its changes are merged into the orchestrator's branch. If a sub-agent fails, its branch is simply deleted — no cleanup needed.

#### Implementation

```swift
protocol GitCheckpointService: Sendable {
    /// Create a named checkpoint (git commit)
    func checkpoint(message: String) async throws
    
    /// Rollback to the last checkpoint
    func rollback() async throws
    
    /// Rollback all the way to session start
    func rollbackToSessionStart() async throws
    
    /// Create a new branch for a sub-agent
    func createSubAgentBranch(name: String) async throws
    
    /// Merge a sub-agent's branch into the parent
    func mergeSubAgentBranch(name: String) async throws
    
    /// Delete a failed sub-agent's branch (cleanup)
    func deleteSubAgentBranch(name: String) async throws
}

// Implementation uses CLI git commands via Process
// No libgit2 or external dependency needed — git is always available on macOS
```

#### What We Track in Memory (Not Git)

Some state is not file-based and doesn't need git:
- Sub-agent task descriptions and progress
- Conversation context (already stored by ConversationManager)
- Resource usage counters (tokens, wall time, cost for OpenRouter)
- Pending human-in-the-loop questions

These are lightweight in-memory structs. If the app crashes, the user re-launches and git tells them exactly what was changed and what wasn't.

### 17.6 Orchestrator ↔ Sub-Agent Bidirectional Conversation

**Key insight**: Sub-agents are NOT fire-and-forget. They maintain a structured conversation channel with the orchestrator. The orchestrator stays at the high level — it doesn't do tactical work — but it knows enough to keep the user informed and unblock sub-agents.

```swift
/// The conversation channel between orchestrator and a sub-agent.
/// Both sides can send and receive messages.
actor SubAgentChannel {
    typealias Message = SubAgentMessage
    
    /// Send a message to the sub-agent (from orchestrator)
    func send(to subAgent: SubAgentID, _ message: Message) async
    
    /// Receive the next message from a sub-agent (orchestrator reads this)
    func receive(from subAgent: SubAgentID) async -> Message
    
    /// Stream all messages from all sub-agents (for the orchestrator's event loop)
    func messageStream() -> AsyncStream<SubAgentMessage>
}

enum SubAgentMessage: Sendable {
    // ── Sub-Agent → Orchestrator ──
    
    /// "I've reached a milestone" (periodic progress)
    case milestoneReached(description: String, completedItems: [String])
    
    /// "I'm stuck, need direction" (blocked)
    case blocked(reason: String, possibleResolutions: [String])
    
    /// "I found something unexpected" (escalation)
    case escalation(
        severity: EscalationSeverity,
        description: String,
        recommendation: String
    )
    
    /// "I need the user to decide something"
    case needsUserInput(question: String, options: [String])
    
    /// "Task complete, here's what I did"
    case completed(summary: String, changes: [FileChange])
    
    /// "I failed" (non-recoverable error)
    case failed(error: String, partialResults: [ToolResult]?)
    
    // ── Orchestrator → Sub-Agent ──
    
    /// "Continue working" (unblock after providing direction)
    case continueWith(direction: String)
    
    /// "Pivot to this instead" (change of plan)
    case pivot(newTask: String, context: String?)
    
    /// "Stop working on this" (cancellation)
    case cancel(reason: String)
    
    /// "Here's the user's answer to your question"
    case userResponse(answer: String)
    
    /// "Merge your branch and report status"
    case statusReport
}
```

#### Conversation Flow (User → Orchestrator → Sub-Agent)

```
User: "Build a REST API client for our CRM"
  ↓
Orchestrator: Creates plan with 3 sub-agents
  ├── Sub-agent 1: "Analyze existing networking layer"
  ├── Sub-agent 2: "Design API schema"
  └── Sub-agent 3: "Implement API client"
  ↓
Orchestrator → User: "I've broken this into 3 tasks. Estimated time: ~5 minutes."
  ↓
[Sub-agent 1 works on branch agent/session-1/sub-task-1]
  ↓
Sub-agent 1 → Orchestrator: milestoneReached("Found 3 networking files, analyzed URLSession usage")
  ↓
Orchestrator → User (UI update): "Analyzing networking layer... found 3 files ✓"
  ↓
Sub-agent 1 → Orchestrator: milestoneReached("Schema extracted, ready for implementation")
  ↓
Sub-agent 1 → Orchestrator: completed(summary: "Network layer uses URLSession with custom delegate pattern")
  ↓
Orchestrator → Sub-agent 3: continueWith(direction: "Use URLSession delegate pattern, not Alamofire")
  ↓
Sub-agent 2 → Orchestrator: blocked(reason: "Two API design approaches possible", 
                                   possibleResolutions: ["RESTful with versioning", "GraphQL"])
  ↓
Orchestrator → User: "Sub-agent needs your input: REST or GraphQL for the CRM API?"
  ↓
User: "REST with versioning"
  ↓
Orchestrator → Sub-agent 2: userResponse(answer: "REST with versioning, /v1/ prefix")
  ↓
[Sub-agent 2 continues...]
  ↓
Orchestrator → User (periodic update): 
  "Database schema: done ✓ | API endpoints: 4/12 done | Frontend: awaiting schema"
  ↓
[All sub-agents complete, orchestrator merges branches, runs QA]
  ↓
Orchestrator → User: 
  "CRM API client built. Summary:
   - 3 new files, 245 lines added
   - 2 existing files modified
   - auth/rate-limiting/logging included
   Review and adjust as needed."
```

#### Orchestrator's Situational Awareness

The orchestrator maintains a lightweight summary of all sub-agents:

```swift
actor OrchestratorState {
    private var subAgents: [SubAgentID: SubAgentStatus] = [:]
    
    struct SubAgentStatus: Sendable {
        let id: SubAgentID
        let taskDescription: String
        var status: Status
        var lastMilestone: String?
        var blockedSince: Date?
        var startedAt: Date
        var toolCallsUsed: Int
        var branchName: String
        
        enum Status: String, Sendable {
            case running
            case blocked
            case awaitingUserInput
            case completed
            case failed
            case cancelled
        }
    }
    
    /// Human-readable summary for the user
    var userSummary: String {
        subAgents.values.map { agent in
            let status = agent.status.rawValue
            let milestone = agent.lastMilestone.map { ": \($0)" } ?? ""
            return "- \(agent.taskDescription): \(status)\(milestone)"
        }.joined(separator: "\n")
    }
}
```

### 17.7 Resource Governance

Background jobs are not free. Need limits:

```swift
struct BackgroundJobGovernor {
    var maxActiveJobs: Int = 3
    var maxTotalTokensPerJob: Int = 1_000_000     // approximate
    var maxWallTimePerJob: Duration = .minutes(30)
    var maxToolCallsPerJob: Int = 500
    var allowSubAgentChaining: Bool = false         // sub-agents spawning sub-agents
    var modelTier: ModelTier = .cheapestAvailable    // sub-agents use cheaper models
}
```

### 17.7 Design Patterns Applied

| Pattern | Where |
|---------|-------|
| **AsyncSequence / AsyncStream** | Progress streaming from background jobs |
| **Actor isolation** | Job state owned by `BackgroundJobManager` actor |
| **Command pattern** | `spawn_sub_agent` is a tool, returns a `JobHandle` |
| **Repository pattern** | `GitCheckpointService` manages git-based session safety |
| **Circuit Breaker** | If sub-agent fails N times, mark as dead |
| **Dead Letter Queue** | Failed jobs go to a review queue |
| **Resource Governor** | Limits on concurrent jobs, tokens, wall time |

---

## 18. Design Patterns — The Full Architecture Map

### 18.1 Pattern Inventory

| Pattern | Where It Fits | Status Today |
|---------|---------------|-------------|
| **Registry** | Tool discovery & query | ❌ Missing |
| **Strategy** | Model adapters (OpenRouter vs Gemma vs MCP) | ❌ Ad-hoc |
| **Command** | Each tool call is a command; executor is invoker | ⚠️ Partial |
| **Composite** | Batch of tools is a composite; sub-agent is a composite | ❌ Missing |
| **Chain of Responsibility** | Sandbox layers (path → network → terminal → mode) | ⚠️ Partial (PathValidator only) |
| **Observer** | Progress reporting, telemetry, UI updates | ✅ Works (via EventBus) |
| **State Machine** | Tool lifecycle (queued → executing → completed/failed) | ❌ Implicit |
| **DAG Scheduler** | Parallel tool execution with dependency resolution | ❌ Missing |
| **Facade** | `ToolExecutor` as facade over scheduler + sandbox + telemetry | ✅ Works |
| **Builder** | Building `ToolDefinition` with many optional fields | ❌ Manual today |
| **Dependency Injection** | All tool dependencies injected | ⚠️ Partial (some singletons remain) |
| **Actor** | Isolated state (`ToolScheduler`, `BackgroundJobManager`) | ✅ Works (ToolScheduler) |
| **Repository** | Tool definitions, checkpoint store, telemetry store | ❌ Missing |
| **Null Object** | No-op telemetry, no-op file system for tests | ❌ Missing |
| **Decorator** | Wrap tool execution with logging/timing/sandbox checks | ❌ Missing |
| **Circuit Breaker** | Sub-agent failure handling | ❌ Missing |
| **Resource Governor** | Background job limits | ❌ Missing |
| **Event Sourcing** | Tool execution log as sequence of events | ❌ NDJSON logging exists but not true event sourcing |

### 18.2 Pattern Details for Key Components

#### Registry Pattern (Tools)

```swift
final class ToolRegistry: Sendable {
    // Classic registry pattern — tools register themselves
    func register(_ tool: ToolDefinition)
    
    // Query by capability (Strategy-like selection)
    func tools(for capabilities: Set<ToolCapability>) -> [ToolDefinition]
    
    // Thread-safe (actor or lock)
}
```

#### Decorator Pattern (Sandbox)

```swift
protocol ToolExecutor {
    func execute(_ call: ToolCall, context: ExecContext) async throws -> ToolResult
}

struct SandboxDecorator: ToolExecutor {
    let inner: ToolExecutor
    let pathValidator: PathValidator
    let networkPolicy: NetworkPolicy
    
    func execute(_ call: ToolCall, context: ExecContext) async throws -> ToolResult {
        // 1. Check if tool is allowed in current mode
        try checkMode(call, context.mode)
        
        // 2. Validate all path arguments
        try await validatePaths(call)
        
        // 3. Check network policy
        try checkNetwork(call)
        
        // 4. Delegate to inner executor
        return try await inner.execute(call, context: context)
    }
}

struct TelemetryDecorator: ToolExecutor {
    let inner: ToolExecutor
    let telemetry: ToolTelemetry
    
    func execute(_ call: ToolCall, context: ExecContext) async throws -> ToolResult {
        let start = Date()
        let result = try await inner.execute(call, context: context)
        telemetry.recordExecution(call: call, duration: start.distance(to: .now), result: result)
        return result
    }
}

// Usage:
let executor = TelemetryDecorator(
    inner: SandboxDecorator(
        inner: RealToolExecutor(registry: registry, scheduler: scheduler),
        pathValidator: pathValidator,
        networkPolicy: networkPolicy
    ),
    telemetry: telemetry
)
```

#### Composite Pattern (Sub-Agent / Batch)

```swift
protocol Executable: Sendable {
    func execute(context: ExecContext) async throws -> ExecutionResult
}

struct ToolCallExecution: Executable {
    let toolCall: ToolCall
    let definition: ToolDefinition
    // ...
}

struct BatchExecution: Executable {
    let executions: [Executable]
    let strategy: BatchStrategy  // .sequential, .parallel, .dag
    
    func execute(context: ExecContext) async throws -> ExecutionResult {
        switch strategy {
        case .sequential:
            var results: [ToolResult] = []
            for exec in executions {
                results.append(try await exec.execute(context: context))
            }
            return ExecutionResult(results: results)
        case .parallel:
            return try await withThrowingTaskGroup(...) { ... }
        case .dag:
            return try await DAGScheduler(executions).execute()
        }
    }
}

struct SubAgentExecution: Executable {
    let taskDescription: String
    let agentConfig: AgentConfiguration
    let progressStream: AsyncStream<JobProgress>
    
    func execute(context: ExecContext) async throws -> ExecutionResult {
        // Spawn a background task
        // Run with restricted tool access
        // Stream progress
        // Return accumulated result
    }
}
```

### 18.3 What These Patterns Solve Together

| Problem | Pattern | How |
|---------|---------|-----|
| "Adding a new tool touches 3 files" | **Registry** + **Builder** | Register once, auto-discovery |
| "Can't test tool X without the real file system" | **DI** + **Decorator** + **Null Object** | Inject in-memory FS, no-op telemetry |
| "Write tool blocks UI for 2s" | **Actor** + **DAG Scheduler** | Non-MainActor execution, parallel dispatch |
| "Sub-agent goes rogue, eats context" | **Resource Governor** + **Circuit Breaker** | Hard limits, auto-kill |
| "Sandbox check logic is duplicated in every tool" | **Decorator** | One decorator wraps all tools |
| "Can't pause a long agent run" | **State Machine** + **Checkpoint** | Pause/resume via persisted state |

---

## 19. What Else Should We Think About

Things I noticed during the deep-dive that don't fit neatly into the above categories:

### 19.1 Tool Call Recovery & Repetition Detection (Current Home: ToolLoopHandler)

The 2,775-line `ToolLoopHandler` is mostly repetition detection (signatures, hashes, recovery). This should be a separate component:

```swift
actor ToolLoopGuard {
    // Detects and prevents:
    // - Repeated identical tool batches
    // - Repeated same-content responses without tool calls
    // - Repeated mutation targets
    // - Read-only tool loops that never make progress
    // - Failed tool calls being retried with same arguments
    // - Assistant update duplicates
    
    func check(_ context: LoopContext) -> LoopDecision {
        // Returns: .continue, .stop(reason), .recover(suggestion), .forceFollowup
    }
}
```

This is a **pure function / actor** — it takes context, returns a decision. No MainActor, no UI, no services. Testable in isolation.

### 19.2 Token Budget Management

The model has a finite context window. Tools consume it in two ways:
1. **Tool descriptions** in the system prompt (fixed cost)
2. **Tool results** in the conversation (variable cost)

We need a `TokenBudget` component that:
- Estimates token cost per tool definition (via `PromptMaterial` variant selection)
- Estimates token cost per tool result (via text length)
- Can truncate/compress tool results when budget is tight
- Can drop low-priority tool descriptions from the prompt
- Reports budget usage back to the model ("response truncated, X tokens used")

### 19.3 Tool Result Compression

Large tool results (terminal output, file reads, web page content) consume context fast. Strategies:
- **Line range**: read only requested lines (already done)
- **Auto-truncation**: cap at N characters with truncation marker
- **Summarization**: use a cheap model to summarize tool results before injecting
- **Delta compression**: for repeated reads of the same file, only return changes
- **Semantic chunking**: return the N most relevant chunks instead of the full file

### 19.4 Agent Memory (Beyond Conversation)

The agent needs persistent memory across conversation turns:
- **Conversation summaries**: "We already analyzed the networking layer"
- **Decision records**: "User chose Option B for the refactoring approach"
- **File state knowledge**: "We last modified NetworkManager.swift 3 turns ago"
- **Rejection history**: "Don't try to modify Podfile again (user said no)"

This is related to the `IndexAddMemoryTool` / `IndexListMemoriesTool` but those are dumb key-value stores. We need structured agent memory.

### 19.5 Tool Execution Traceability

When things go wrong (model loops, writes wrong file, deletes something), we need the full trace:

```swift
struct ToolExecutionTrace: Codable, Sendable {
    let sessionId: String
    let conversationId: String
    let runId: String
    let events: [TraceEvent]
}

struct TraceEvent: Codable, Sendable {
    let timestamp: Date
    let type: EventType  // .toolCall, .toolResult, .modelResponse, .humanInput, .error
    let data: [String: String]
    let parentId: String?  // For sub-agent tracing
}
```

The trace should be:
- Structured (not ad-hoc NDJSON)
- Filterable (by conversation, tool type, user)
- Replayable (simulate the same tool calls to reproduce bugs)
- Viewable in a debug UI (tree view of tool calls with timing)

### 19.6 Error Boundary Architecture

Errors can happen at multiple levels. Each level should be handled independently:

```
Model Error (bad JSON, no tool calls)
  → Recoverable: retry with stricter prompt
  → Unrecoverable: return error to user

Tool Execution Error (file not found, permission denied)
  → Recoverable: try alternative path, suggest fix
  → Unrecoverable: return error as tool result (model sees it)

Orchestration Error (max transitions exceeded)
  → Recoverable: return partial results with "I was interrupted"
  → Unrecoverable: only if graph is corrupted

Sub-Agent Error (background job crashed)
  → Recoverable: restart with checkpoint
  → Unrecoverable: move to dead letter queue

Infrastructure Error (DB locked, disk full)
  → Always recoverable at outer level: retry after delay
  → Unrecoverable: only if hardware is failing
```

### 19.7 Testing the Full Stack

Beyond unit tests, we need:

**Integration tests** that run the full orchestration with mock AI responses:
```
Given: mock model returns tool_calls for search_project + read_file
When: orchestrator runs
Then: tools execute in correct order
And: results feed back to mock model
And: orchestrator terminates after N tool loops
```

**Fault injection tests**:
```
Given: read_file tool throws "file not found"
When: orchestrator runs
Then: model gets error result
And: orchestrator continues (doesn't crash)
```

**Background job tests**:
```
Given: sub-agent spawns with task "list files"
When: user provides input 10s later
Then: sub-agent receives input and continues
And: final result includes both initial + post-input work
```

**Performance benchmarks** (CI-gated):
```
Tool dispatch overhead < 100μs
Batch of 10 independent reads < 2× single read latency
DAG scheduler overhead < 500μs for 20-node graph
```

---

## 20. Summary: What the Full Architecture Looks Like

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           UI LAYER                                       │
│  Job Panel │ Progress Stream │ Trace Viewer │ Background Job Controls     │
├──────────────────────────────────────────────────────────────────────────┤
│                       ORCHESTRATION LAYER                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  DAGOrchestrationRunner (actor, non-MainActor)                  │   │
│  │  ├─ OrchestrationGraph (true DAG, not linear)                  │   │
│  │  ├─ OrchestrationState (Codable, persistable)                  │   │
│  │  ├─ BackgroundJobManager (actor, resource-governed)            │   │
│  │  └─ GitCheckpointService (git-native safety)                  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────────┤
│                      TOOL EXECUTION LAYER                                │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  ToolRegistry (thread-safe)                                     │   │
│  │  ├─ ToolDefinition (value type, Codable)                        │   │
│  │  ├─ ToolCapabilities + ToolSideEffects                          │   │
│  │  └─ PromptMaterial (concise/standard/comprehensive)             │   │
│  │                                                                  │   │
│  │  ToolExecutor (decorator chain, non-MainActor)                  │   │
│  │  ├─ SandboxDecorator → NetworkPolicyDecorator → TelemetryDeco  │   │
│  │  ├─ DAGScheduler (parallel + dependencies)                     │   │
│  │  ├─ ToolScheduler (actor, read/write concurrency)              │   │
│  │  └─ ToolLoopGuard (actor, repetition detection)                │   │
│  └──────────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────────┤
│                      MODEL ADAPTER LAYER                                 │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  ToolFormatAdapter (protocol)                                   │   │
│  │  ├─ OpenRouterToolAdapter                                       │   │
│  │  ├─ GemmaToolAdapter                                            │   │
│  │  └─ MCPToolAdapter (future)                                     │   │
│  └──────────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────────┤
│                      INFRASTRUCTURE                                      │
│  Telemetry │ Crash Recovery │ File System (protocol) │ Sandbox          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 21. Three-Tier Agent Modes

### 21.1 The Shortfall of Two Modes

Today: `Chat` (no tools) and `Agent` (all tools). This is a binary on/off for tool access:

| Request | Chat | Agent |
|---------|------|-------|
| "Explain this function" | ✅ Good | Overkill |
| "Add error handling to this file" | ❌ Can't | Overkill (fires up planner, reviewer, QA loop...) |
| "Build me a CRM for a 5-person real estate company" | ❌ Can't | ✅ Good |

The gap: **Coder Mode** — the default mode. A middle ground where the agent can use tools but doesn't spin up the full orchestration machinery. One turn, focused execution, fast feedback. Agent is opt-in (user chooses it for big tasks).

### 21.2 Three Modes Defined

```
                  CHAT                     CODER                     AGENT
         ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────┐
 Type    │ Conversation       │   │ DEFAULT            │   │ Opt-in (big tasks) │
         │                    │   │ Daily coding       │   │                    │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Scope   │ Read-only Q&A     │   │ Focused coding     │   │ Open-ended build   │
         │ about code         │   │ tasks               │   │ & refactor          │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Tools   │ NONE               │   │ Full toolset       │   │ Full toolset +     │
         │                    │   │                     │   │ agent tools         │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Model   │ ANY model          │   │ ANY model          │   │ Cloud only         │
         │ (no tool support   │   │ (local only if     │   │ (local models lack │
         │  needed)           │   │  model supports    │   │  context & cap-    │
         │                    │   │  tool calling)      │   │  ability for this) │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Exec    │ None (no tools)   │   │ Single turn        │   │ Multi-turn DAG     │
         │                    │   │ Sequential batch   │   │ Parallel execution  │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Sub-    │ ❌ No              │   │ ❌ No              │   │ ✅ Yes              │
 agents  │                    │   │                     │   │                     │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Back-   │ ❌ No              │   │ ❌ No              │   │ ✅ Yes              │
 ground  │                    │   │                     │   │                     │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Human-  │ ❌ No              │   │ ✅ Yes (limited)   │   │ ✅ Yes (full)      │
 in-loop │                    │   │ "File exists,      │   │ "I found 3          │
         │                    │   │  overwrite?"        │   │ approaches, pick?"  │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Latency │ <1s                │   │ 2-30s              │   │ 30s - hours         │
         ├────────────────────┤   ├────────────────────┤   ├────────────────────┤
 Cost    │ Varies by model    │   │ Varies by model    │   │ High ($$$)          │
         │ (no API calls)      │   │ (API calls for     │   │ (many API calls,    │
         │                     │   │  tool execution)    │   │  sub-agent calls)   │
         └────────────────────┘   └────────────────────┘   └────────────────────┘
```

### 21.3 Mode Configuration as a First-Class Value

```swift
struct ModeConfiguration: Sendable {
    // -- Tool Access --
    var allowedCapabilities: Set<ToolCapability>  // which tool categories are available
    var excludedToolNames: Set<String>            // fine-grained exclusions
    
    // -- Execution Model --
    var schedulingStrategy: SchedulingStrategy    // .none, .sequential, .dag
    var maxToolCallsPerTurn: Int                  // 0 (chat), 50 (coder), 500 (agent)
    var maxToolIterations: Int                    // 0, 1, unlimited
    var maxSubAgentDepth: Int                     // 0, 0, 3
    
    // -- Background Work --
    var allowBackgroundJobs: Bool
    var maxActiveBackgroundJobs: Int
    
    // -- Model Selection --
    var defaultModel: ModelTier                   // .localFast, .cloudCheap, .cloudPowerful
    var allowModelOverride: Bool                  // user can pick a different model
    
    // -- Resource Limits --
    var contextBudgetTokens: Int
    var maxWallTime: Duration
    var maxTotalCost: Double?                     // user-set budget cap
    
    // -- Human Interaction --
    var allowHumanInTheLoop: Bool                 // agent can pause and ask the user
    var autoConfirmMutations: Bool                // coder: auto-confirm, agent: batch review
    
    // -- Sandbox --
    var sandbox: SandboxConfiguration
    
    /// Determine if this mode is available for the given model type.
    /// Local models (Gemma 4 E4B) cannot run Coder or Agent modes
    /// because they lack reliable tool-calling capability and context window capacity.
    func isAvailableForModel(_ model: ModelTier) -> Bool {
        switch self.modeName {
        case .chat:  return true   // ALL models can do chat
        case .coder: return model != .localFast  // local can't do tools reliably
        case .agent: return model == .cloudPowerful  // cloud only
        }
    }
    
    // ========== Presets ==========
    
    static let chat = ModeConfiguration(
        allowedCapabilities: [],
        excludedToolNames: [],
        schedulingStrategy: .none,
        maxToolCallsPerTurn: 0,
        maxToolIterations: 0,
        maxSubAgentDepth: 0,
        allowBackgroundJobs: false,
        maxActiveBackgroundJobs: 0,
        defaultModel: .userSelected,  // respects whatever model the user chose
        allowModelOverride: true,     // user can switch models freely
        contextBudgetTokens: 128_000,
        maxWallTime: .seconds(30),
        maxTotalCost: nil,
        allowHumanInTheLoop: false,
        autoConfirmMutations: false,
        sandbox: SandboxConfiguration.readOnly
    )
    
    static let coder = ModeConfiguration(
        allowedCapabilities: [.fileRead, .fileWrite, .fileDelete, .fileSearch,
                              .directoryList, .indexSearch, .indexSemantic,
                              .indexMemory, .projectStructure, .webSearch, .commandExecution],
        excludedToolNames: [],
        schedulingStrategy: .sequential,
        maxToolCallsPerTurn: 50,
        maxToolIterations: 1,       // single turn
        maxSubAgentDepth: 0,        // no sub-agents
        allowBackgroundJobs: false,
        maxActiveBackgroundJobs: 0,
        defaultModel: .cloudBalanced,
        allowModelOverride: true,
        contextBudgetTokens: 128_000,
        maxWallTime: .minutes(5),
        maxTotalCost: 0.50,         // $0.50 max per request
        allowHumanInTheLoop: true,
        autoConfirmMutations: true,
        sandbox: SandboxConfiguration.projectReadWrite
    )
    
    static let agent = ModeConfiguration(
        allowedCapabilities: .all,
        excludedToolNames: ["spawn_sub_agent"], // sub-agent spawning uses different mechanics
        schedulingStrategy: .dag,
        maxToolCallsPerTurn: 500,
        maxToolIterations: .max,    // unlimited turns (up to wall time)
        maxSubAgentDepth: 3,        // sub-agents can spawn sub-sub-agents but only 3 deep
        allowBackgroundJobs: true,
        maxActiveBackgroundJobs: 3,
        defaultModel: .cloudPowerful,
        allowModelOverride: true,
        contextBudgetTokens: 512_000,
        maxWallTime: .hours(2),
        maxTotalCost: 5.00,         // $5 max per session
        allowHumanInTheLoop: true,
        autoConfirmMutations: false, // agent reviews all mutations in batch before applying
        sandbox: SandboxConfiguration.projectReadWrite  // + explicit network policy
    )
}
```

### 21.4 Mode-Adaptive Orchestration

The same orchestration infrastructure adapts its behavior based on mode:

```swift
actor ModeOrchestrator {
    private let modeConfig: ModeConfiguration
    
    func handle(request: UserRequest) async -> ResponseStream {
        switch modeConfig.schedulingStrategy {
        case .none:
            // Chat mode: direct LLM call, no tools, no loop
            return try await directInference(request)
            
        case .sequential:
            // Coder mode: single LLM call → tools → done
            return try await singleTurnWithTools(request)
            
        case .dag:
            // Agent mode: full DAG orchestration with sub-agents
            return try await agentLoop(request)
        }
    }
}
```

### 21.5 The Tool Execution Pipeline Per Mode

The **key insight**: a tool's `execute()` is identical in all modes. What changes is the **pipeline** around it:

```
CHAT mode:
  User request → Local LLM → Text response
  No tool pipeline exists.

CODER mode:
  User request → LLM (tool_calls) 
    → AIToolExecutor.executeBatch()         ← sequential, no DAG
      → ToolScheduler (read/write locking)
      → Per-tool: SandboxDecorator → TelemetryDecorator → execute()
    → Result → LLM (final response)
  Single turn. No planner, no QA loop, no sub-agents.

AGENT mode:
  User request → Planner (strategic → tactical)
    → Dispatcher → LLM (tool_calls)
      → DAGScheduler.buildGraph()           ← parallel with deps
      → ToolScheduler (read/write locking)
      → Per-tool: SandboxDecorator → TelemetryDecorator → execute()
      → Results → LLM → more tool_calls? → loop
    → QA review → Branch review → More branches?
    → Sub-agents for parallel work
    → Background jobs for async work
    → Final response (or "still working, here's my progress")
```

### 21.6 Tool Compatibility: Same Tool, Different Scope

Your requirement: **"a single tool might be executed in different scope of work"**.

This is handled by the **SandboxDecorator** which applies mode-appropriate scoping:

```swift
struct SandboxDecorator: ToolExecutor {
    let inner: ToolExecutor
    let modeConfig: ModeConfiguration
    
    func execute(_ call: ToolCall, context: ExecContext) async throws -> ToolResult {
        // Step 1: Is this tool allowed in this mode?
        guard modeConfig.allowedCapabilities.contains(call.requiredCapability) else {
            throw ToolError.notAvailableInMode(
                tool: call.toolName,
                mode: modeConfig.modeName,
                availableCapabilities: modeConfig.allowedCapabilities
            )
        }
        
        // Step 2: Apply mode-specific sandbox rules
        let sandboxedCall = try applyModeSandbox(call)
        
        // Step 3: Delegate to actual execution
        return try await inner.execute(sandboxedCall, context: context)
    }
    
    /// Mode-specific sandbox rules:
    /// - Chat:          ALL tools blocked at capability level (fast path)
    /// - Coder:         All capabilities allowed, but max tool calls enforced
    /// - Agent:         All capabilities + agent tools, but sub-agent chaining limited
    private func applyModeSandbox(_ call: ToolCall) throws -> ToolCall {
        // Per-mode argument mutation
        switch modeConfig.modeName {
        case .coder:
            // Coder: restrict file writes to files the agent has already read
            // (prevent writing to completely unknown files)
            if call.sideEffect == .writesFile {
                guard ledger.hasRead(relativePath: call.targetPath) else {
                    throw ToolError.writeWithoutPriorRead(path: call.targetPath)
                }
            }
        case .agent:
            // Agent: full access, but log all mutations for batch review
            pendingMutationReview.append(call)
        default:
            break
        }
        return call
    }
}
```

### 21.7 Mode Transitions (Escalation)

A user shouldn't be locked into a mode. They should be able to **escalate**:

```
User: "What does this function do?"
  → Chat mode (local model, <1s, free)

User: "Actually, add error handling to it."
  → Escalate to Coder mode (cloud model, tools, $0.02)

User: "Now build me a full test suite for this module."
  → Escalate to Agent mode (full orchestration, sub-agents, ~$0.50)
```

**Escalation rules**:

```swift
enum ModeTransition: Sendable {
    case stay(ModeConfiguration)
    case escalate(to: ModeConfiguration, reason: String)
    case deescalate(to: ModeConfiguration, reason: String)
}

struct ModePolicy {
    /// Only escalate, never de-escalate automatically
    static let allowEscalation: ModePolicy
    
    /// User can manually switch to any mode
    static let allowFreeSwitch: ModePolicy
    
    /// Auto-escalate when user intent is detected (e.g., "build", "create", "refactor")
    static let autoEscalate: ModePolicy
}
```

The **orchestrator** decides escalation by analyzing user intent:

```swift
enum IntentClassifier {
    static func classify(_ input: String) -> UserIntent {
        // "explain", "what is", "how does" → .question
        // "add", "fix", "change", "update" → .task
        // "build", "create", "migrate", "implement" → .project
    }
}

struct EscalationPolicy {
    func transition(from current: ModeConfiguration, intent: UserIntent) -> ModeTransition {
        switch (current, intent) {
        case (.chat, .question):   return .stay(current)
        case (.chat, .task):       return .escalate(to: .coder, reason: "Task requires tools")
        case (.coder, .project):   return .escalate(to: .agent, reason: "Project requires full orchestration")
        case (.agent, .question):  return .deescalate(to: .chat, reason: "Simple question, save cost")
        default:                   return .stay(current)
        }
    }
}
```

### 21.8 Impact on Tool Architecture

The three-mode system **validates** the Decorator + Strategy approach. Here's why:

| Tool Architecture Decision | Why It Supports 3 Modes |
|---------------------------|------------------------|
| **Tool is a pure executor** | Same `execute()` in all modes. Mode policy is applied by decorators. |
| **Capability-based filtering** | Mode config declares `allowedCapabilities`. Registry filters tools. No mode-specific code in tools. |
| **Decorator chain** | SandboxDecorator applies different rules per mode. TelemetryDecorator tracks cost per mode. |
| **DAG scheduler** | Only Agent mode uses it. Coder uses sequential. Chat doesn't execute tools at all. Same scheduler class, different config. |
| **Sub-agent system** | Only Agent mode allows it. Coder mode rejects `spawn_sub_agent` calls at the capability check. |
| **Prompt material variants** | Chat: concise descriptions only. Coder: standard + examples. Agent: comprehensive + guidance. Same tool definitions, different prompt assembly. |
| **Resource governor** | Per-mode limits on tokens, wall time, cost. Governor reads from `ModeConfiguration`. |
| **Sandbox** | Chat: read-only by default. Coder: read-write within project. Agent: read-write + network + terminal. Same `SandboxConfiguration`, different presets. |

### 21.9 Implementation Priority

```
Phase 1: Refactor AIMode from enum to ModeConfiguration-backed value
         (AIMode.swift becomes a thin wrapper, ModeConfiguration holds the logic)
         
Phase 2: Add Coder mode alongside existing Chat/Agent
         (mostly works today — "agent" is already close to coder. Rename + adjust.)
         
Phase 3: Build Agent mode on top of:
         - DAGScheduler (section 15)
         - BackgroundJobManager + sub-agent tools (section 17)
         - GitCheckpointService for session safety (section 17.5)
         - Orchestrator↔Sub-agent bidirectional comms (section 17.6)
         - Mode escalation logic (section 21.7)
         
Phase 4: Analytics to validate the model
         - How often do users switch modes?
         - What's the average cost per mode per request?
         - How often does auto-escalation guess wrong?
```

#### UI Enforcement: Local Model Mode Restrictions

When the user selects a local model (Gemma 4 E4B), the UI enforces mode availability:

| Model | Chat | Coder | Agent |
|-------|------|-------|-------|
| Local (Gemma 4 E4B) | ✅ Available | ❌ Disabled in dropdown | ❌ Disabled in dropdown |
| Cloud (OpenRouter) | ✅ Available | ✅ Available | ✅ Available |

The dropdown behavior:
```
Mode: [Chat ▼]    ← local model: Chat only (Coder/Agent grayed out)
Mode: [Coder ▼]   ← cloud model: all three available, Coder is default
```

When a user switches to a local model while in Coder mode, the UI auto-switches to Chat:
```
"Switched to Chat mode because the selected model (Gemma 4 E4B)
 doesn't support tool calling. Switch to a cloud model for Coder or Agent mode."
```

#### Mode Selector UI (Dropdown)

```
┌──────────────────────────────┐
│ Mode: [Coder ▼]     (default)│
│       Chat                   │
│       Coder                  │ ← default, highlighted
│       Agent                  │ ← shows $ badge
└──────────────────────────────┘
```

- Coder is the DEFAULT mode (selected on app launch)
- Agent shows a small cost badge: `Agent ~$$$`
- Local model selection grays out Coder and Agent with tooltip explaining why
- Mode is per-conversation (switching starts a new conversation context)

### 21.10 Open Questions for the Three Modes

1. **Should modes be user-selectable (dropdown) or auto-detected from intent?** Auto-detection is smoother but can guess wrong. A dropdown is explicit but adds UI complexity.

2. **How does the user see mode boundaries?** If the agent escalates from Chat to Coder, does the UI show a banner? "I switched to Coder mode to edit files."

3. **Cost transparency**: Agent mode could cost $5+. Should there be a "dry run" that estimates cost before executing?

4. **Mode per conversation or per message?** Per-message is more flexible but harder to track. Per-conversation is simpler but locks the user in.

5. **Can Coder mode handle multi-file edits?** Yes — they're just sequential tool calls in one turn. It can't handle multi-step planning or sub-agents.

6. **What context does Agent mode persist between turns?** Git commits for file state (section 17.5), conversation summary for context, sub-agent progress reports. The user should be able to interrupt and resume.

7. **Should Agent mode emit a plan before executing?** "I'm going to: 1) Analyze the codebase, 2) Design the schema, 3) Build 5 modules. Estimated cost: $2. Proceed?" — This builds user trust and lets them cancel expensive runs early.

---

## 22. Patch/Diff Tool — High-Performance Line-Precise File Editing

### 22.1 What It Does

A specialized tool for applying **line-numbered patches/diffs** to files without loading the entire file into memory. Designed for high-throughput agentic workflows where the model can issue 100s of precise edits without the overhead of read-modify-write cycles.

```
Current flow (read_file + replace_in_file):
  read_file(start_line: 10, end_line: 20)  → loads full file, returns 10 lines
  replace_in_file(old: "...", new: "...")   → loads full file, finds old, replaces, writes back
  → 2 file I/O ops, 2 full file loads per edit

Patch tool flow:
  patch_file(path: "src/main.swift", hunks: [{ start: 10, lines: ["+ new line 10", "  line 11"] }])
  → 1 file I/O op, loads only the affected byte regions via mmap
  → Byte-level swapping, no String allocation for unmodified parts
```

### 22.2 Tool Definition

```json
{
  "name": "patch_file",
  "description": "Apply precise line-numbered changes to a file. Faster than read_file + replace_in_file. Each hunk specifies exact line numbers. Can apply multiple hunks in a single call.",
  "parameters": {
    "path": { "type": "string", "description": "File to patch" },
    "hunks": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "start_line": { "type": "integer", "description": "1-based line number to start the hunk" },
          "lines": {
            "type": "array",
            "items": { "type": "string" },
            "description": "Replacement lines. Lines with '+' prefix = addition. '-' prefix = deletion. ' ' prefix = context. No prefix = direct replacement."
          },
          "collapse": { "type": "boolean", "description": "Replace hunk range with … (for collapsing known sections)" }
        },
        "required": ["start_line", "lines"]
      }
    },
    "dry_run": { "type": "boolean", "description": "Validate without applying (returns preview)" }
  },
  "required": ["path", "hunks"]
}
```

### 22.3 Implementation Strategy

**Option A: Custom high-performance implementation (recommended for research)**

```
1. mmap() the file (zero-copy, no String allocation for unmodified parts)
2. Parse hunks, sort by start_line (descending = safe, line numbers shift on insert)
3. For each hunk:
   a. Validate start_line ≤ file line count
   b. If lines have +/- prefix: apply diff logic (insert/delete lines)
   c. If lines have no prefix: direct replacement
4. Build new content buffer (copy unchanged lines from mmap, splice hunk lines)
5. Write back via atomic rename (write to temp file, rename() over original)
6. Return {status: "success", linesChanged: 3, newChecksum: "abc123"}
```

Performance:
- **No full-file String** — Data buffers + line-index scanning
- **O(n)** for reading + constructing new content (n = file lines)
- **O(h)** for the hot path (h = hunk lines to validate)
- **Atomic writes** via `rename()` syscall — never corrupts files
- **Dry run** in ~100μs (count lines, validate hunks, no I/O)

For 100s of concurrent calls:
- Different files → fully parallel (per-file mmap)
- Same file → serialized by `ToolScheduler` per-path write lock

**Option B: Wrap system `patch` command**

```swift
let diff = generateUnifiedDiff(originalLines, newLines)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/patch")
process.arguments = [filePath]
```

Pros: Leverages battle-tested `patch`, handles merges/conflicts
Cons: ~5ms process spawn overhead per call, not suitable for 100s concurrent, harder to sandbox

### 22.4 When to Use Which Tool

| Tool | Use For | Characteristics |
|------|---------|-----------------|
| `write_file` | New files, complete rewrites | Simple, one op per file |
| `replace_in_file` | Text by content match | Fuzzy matching, great for small changes |
| **`patch_file`** | **Precise line-numbered edits, bulk ops** | **Fast, parallel, no fuzzy matching** |

System prompt guidance:
```
You have three editing tools:
1. write_file — Use for NEW files or COMPLETE rewrites
2. replace_in_file — Use when you know the EXACT text to replace
3. patch_file — Use for PRECISE LINE-NUMBERED edits. Fastest option.
   PREFERRED for bulk or parallel editing.
```

### 22.5 Performance Targets

| Scenario | Current (read+replace) | patch_file |
|----------|----------------------|------------|
| Single-line change in 1000-line file | ~2ms (full file load × 2) | ~0.3ms (mmap + byte swap) |
| 5 edits to same file | ~10ms (5 full cycles) | ~1ms (1 call, 5 hunks) |
| 100 concurrent edits to 100 files | ~200ms (serialized by tool) | ~30ms (parallel, per-file) |
| Dry run (validate only) | Not supported | ~100μs per file |

### 22.6 Open Questions

1. **mmap vs DispatchIO** — Is mmap safe for concurrent reads on the same file? POSIX says yes (MAP_SHARED). DispatchIO is an alternative with async I/O built in.

2. **Unicode safety** — Line counting is safe for UTF-8 (newline is always 0x0A). But what about mixed line endings (CRLF vs LF)?

3. **Patch format** — Should we support unified diff format (model-friendly) as well as JSON hunks (tool-friendly)? Both?

4. **Conflict detection** — If two hunks overlap in the same call: fail the whole call? Apply in order (last wins)? Merge?
