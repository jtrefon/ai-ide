# Streaming Pipeline Architecture

## Current Pain Points

| # | Problem | Root Cause |
|---|---|---|
| 1 | Gemma parser duplicated 5× | No single source of truth per format |
| 2 | Cloud models never stream to UI | No unified event pathway; cloud returns `AIServiceResponse` only |
| 3 | 35+ regex patterns strip markup | No structured event model; all processing is ad-hoc string manipulation |
| 4 | Textual tool-call detection fragile | Heuristic-based classification instead of deterministic parser dispatch |
| 5 | Reasoning extraction in 3 places | No shared reasoning parser |
| 6 | Tool loop stall recovery produces garbage | FinalResponseHandler fallback is defeatist, not grounded |
| 7 | `clearStreamingBuffer` timing causes UI flicker | No pipeline lifecycle; buffer clears are ad-hoc |

---

## Architecture: Event-Sourced Multi-Stage Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                        EVENT PIPELINE                            │
│                                                                  │
│  Source ──▶ Stage[0] ──▶ Stage[1] ──▶ Stage[N] ──▶ Sink         │
│   (SSE /     (tokenize)  (classify)     (parse       (output)    │
│    MLX)                               tool calls)                │
│                                                                  │
│  Every stage:                                                     │
│    - is a protocol (PipelineStage: 2 methods)                     │
│    - transforms events in isolation                              │
│    - is independently testable                                   │
│    - receives → emits events (no side channels)                   │
│                                                                  │
│  State: PipelineReducer pure function                             │
│    - all state accumulation in one place                          │
│    - no stateful stages (stages are stateless transformers)       │
│                                                                  │
│  Parsing: ParserRegistry (Strategy pattern)                       │
│    - each format = one class conforming to ToolCallFormatParser   │
│    - registry is dynamically extensible (OCP)                     │
│    - no more 5× duplicated Gemma parser                          │
│                                                                  │
│  UI: StreamingUIAdapter (Observer)                                │
│    - subscribes to pipeline output events                         │
│    - updates SwiftUI on every segment                             │
│    - works identically for cloud + local                          │
└──────────────────────────────────────────────────────────────────┘
```

---

## Layer-by-Layer Design

### Layer 0 — Domain Primitives

```swift
/// Every piece of streaming output is classified into one of these.
enum SegmentKind: Sendable, Equatable {
    case userVisible
    case reasoning
    case toolCallMarkup
    case status
    case error
}

/// A classified text segment with full provenance.
struct Segment: Sendable {
    let kind: SegmentKind
    let text: String
    let source: String             // model/provider identifier
    let timestamp: ContinuousClock.Instant
    let metadata: [String: AnyHashable]
}
```

### Layer 1 — Event Model (Universal Currency)

```swift
/// Immutable event. Every stage consumes and produces these.
/// This is the universal currency of the entire pipeline.
enum PipelineEvent: Sendable {
    /// A text segment with classification
    case segment(Segment)
    /// A tool call was opened (first indication)
    case toolCallOpened(id: String, tool: String)
    /// Partial arguments for an open tool call
    case toolCallArguments(id: String, fragment: String)
    /// A tool call was fully received and parsed successfully
    case toolCallCompleted(id: String, tool: String, arguments: [String: Any])
    /// A tool call was received but arguments failed to parse
    case toolCallFailed(id: String, tool: String, rawArguments: String, error: String)
    /// Provider-level status or usage info
    case status(provider: String, info: StatusInfo)
    /// End of stream
    case finished
    /// Error
    case error(StreamError)
}
```

### Layer 2 — PipelineStage Protocol

```swift
/// A single transformation in the streaming pipeline.
/// 
/// SRP: Each stage does exactly one thing.
/// ISP: Two methods — process() and flush().
protocol PipelineStage: AnyObject, Sendable {
    var identifier: String { get }
    
    /// Transform an incoming event into zero or more outgoing events.
    func process(_ event: PipelineEvent) -> AsyncStream<PipelineEvent>
    
    /// Called when the stream ends. Stages that buffer data flush here.
    func flush() -> AsyncStream<PipelineEvent>
}
```

### Layer 3 — EventPipeline (Composable Graph)

```swift
/// Directed acyclic graph of PipelineStages.
///
/// OCP: Add new behavior by inserting stages, not modifying existing ones.
final class EventPipeline: @unchecked Sendable {
    func insert(_ stage: PipelineStage, after predecessor: PipelineStage)
    func remove(_ stage: PipelineStage)
    func replace(_ stage: PipelineStage, with replacement: PipelineStage)
    
    func ingest(_ event: PipelineEvent)
    func finish()
    
    func observe(_ handler: @escaping (PipelineEvent) -> Void) -> any Cancellable
}
```

### Layer 4 — Parser Registry (Strategy Pattern)

```swift
/// One parser per tool-call wire format (SRP, DRY).
protocol ToolCallFormatParser: Sendable {
    var formatIdentifier: String { get }
    /// Parse text incrementally; may receive partial chunks
    func parse(_ text: String) -> [RawToolCall]
    /// Called at EOS for any buffered partial matches
    func finalize() -> [RawToolCall]
}

/// Dynamically extensible. New format → new parser class → register.
final class ParserRegistry: @unchecked Sendable {
    static let shared: ParserRegistry
    func register(_ parser: ToolCallFormatParser)
    func allParsers() -> [ToolCallFormatParser]
}

// ── Each format gets its OWN file (DRY) ──

final class OpenAISSEToolCallParser: ToolCallFormatParser { ... }
final class JSONTagToolCallParser: ToolCallFormatParser { ... }
final class XMLFunctionToolCallParser: ToolCallFormatParser { ... }
final class GemmaToolCallParser: ToolCallFormatParser { ... }     // one file, not 5
final class GLM4ToolCallParser: ToolCallFormatParser { ... }
final class MistralToolCallParser: ToolCallFormatParser { ... }
final class KimiK2ToolCallParser: ToolCallFormatParser { ... }
final class PythonicToolCallParser: ToolCallFormatParser { ... }
final class Llama3ToolCallParser: ToolCallFormatParser { ... }
final class MiniMaxM2ToolCallParser: ToolCallFormatParser { ... }
```

### Layer 5 — State Reducer (CQRS)

```swift
/// Pure function. No side effects, no actors, no async.
/// This makes the entire pipeline testable with simple assertions.
enum PipelineReducer {
    static func reduce(state: inout PipelineState, event: PipelineEvent)
}

struct PipelineState: Sendable {
    var content: String
    var reasoning: String?
    var toolCallDrafts: [String: RawToolCall]
    var completedToolCalls: [AIToolCall]
    var malformedToolCalls: [MalformedToolCall]
    var usage: StreamUsage?
    var isComplete: Bool
    
    func toResponse() -> AIServiceResponse { ... }
}
```

### Layer 6 — UI Adapter (Observer)

```swift
/// Bridges pipeline events → SwiftUI updates.
///
/// Works identically for cloud and local models because both paths
/// feed into the same EventPipeline.
final class StreamingUIAdapter {
    func attach(to pipeline: EventPipeline)
    func detach()
}

// In ConversationManager:
let pipeline = EventPipeline()
let adapter = StreamingUIAdapter()

// Both paths use the SAME pipeline:
// Cloud: AIService → SSE chunks → pipeline.ingest(chunk)
// Local: MLX → async stream → pipeline.ingest(segment)
adapter.attach(to: pipeline)
```

### Standard Pipeline Topology

```
SSE Chunks
  │
  TokenizerStage ─── parses JSON → emits .segment events
  │
  ReasoningExtractionStage ─── detects <think>, <ide_reasoning>, channels → emits .reasoning segments
  │
  StructuredToolCallStage ─── SSE delta tool_calls → toolCallOpened/Arguments/Completed
  │
  TextualToolCallStage ─── dispatches remaining text through ParserRegistry.allParsers()
  │
  BufferCoordinatorStage ─── PipelineReducer.reduce() → accumulates state
  │
  ┌─── OutputAdapterStage ─── publishes to EventBus → StreamingUIAdapter → SwiftUI
  │
  └─── AIServiceResponse ─── assembled from PipelineState.toResponse()
```

---

## How It Solves Each Current Problem

| # | Current Problem | Solution |
|---|---|---|
| 1 | Gemma parser 5× duplicated | One `GemmaToolCallParser` in the registry. All paths dispatch to it |
| 2 | Cloud never streams to UI | `OutputAdapterStage` publishes events to the same `EventBus` that `StreamingUIAdapter` subscribes to. Cloud and local both feed into `EventPipeline` |
| 3 | 35+ fragile regex patterns | Each `TokenizerStage` / `ParserStage` handles its own format deterministically. No sequential regex chaining |
| 4 | Tool-call detection fragile | `TextualToolCallStage` runs ALL registered parsers on incoming text. Each parser returns what it recognizes. Unrecognized text passes through as `.userVisible` |
| 5 | Reasoning extraction in 3 places | One `ReasoningExtractionStage`. Single `<think>`/`<ide_reasoning>`/channel parser. All paths use it |
| 6 | Garbage final messages | `PipelineState.toResponse()` always produces a valid `AIServiceResponse` from accumulated state. No second-guessing in `FinalResponseHandler` |
| 7 | UI flicker from clearStreamingBuffer | Pipeline is append-only. No buffer clears. UI appends every `.segment` event. Final response is just the last event |

---

## What Gets Deleted

| File | Status |
|---|---|
| `ChatPromptBuilder.containsTextualToolCallMarkup` | Replaced by `TextualToolCallStage` |
| `ChatPromptBuilder.stripTextualToolCallMarkup` (35 regex patterns) | Replaced by parser dispatch |
| `ChatPromptBuilder.splitReasoning` (3-parser reasoning) | Replaced by `ReasoningExtractionStage` |
| `ToolLoopUtilities.containsLiteralToolCallMarkup` | Replaced by registered parser |
| `ToolCallFallbackParser.swift` (entire file, 7 decoders) | Replaced by `ParserRegistry` with individual classes |
| `StreamingOutputBuffer.swift` tool-text heuristics | Replaced by `Segment.kind` classification |
| `LocalModelProcessAIService.NativeMLXGenerator.parseGemmaToolCalls` (duplicate #3) | Deleted; uses `GemmaToolCallParser` from registry |
| Gemma parsing in `ChatPromptBuilder` (duplicate #4) | Deleted; uses `GemmaToolCallParser` |
| `clearStreamingBuffer` closure chain | Replaced by append-only pipeline |

---

## Implementation Phases

### Phase 1: Foundation (this PR)
- `PipelineEvent`, `PipelineStage`, `EventPipeline`, `PipelineState`, `PipelineReducer`
- Graph topology + observation mechanism
- Unit tests for pipeline wiring

### Phase 2: Core Stages
- `TokenizerStage` (SSE JSON → events)
- `ReasoningExtractionStage` (single unified parser)
- `BufferCoordinatorStage` (PipelineReducer)
- Integration test: SSE → events → AIServiceResponse

### Phase 3: Parser Registry + First Ports
- `ToolCallFormatParser` protocol
- `ParserRegistry` with dynamic registration
- Port `OpenAISSEToolCallParser`, `JSONTagToolCallParser`, `XMLFunctionToolCallParser`
- Integration test: all 3 parsers with known inputs

### Phase 4: Port All Remaining Parsers
- `GemmaToolCallParser` (replaces 5 scattered implementations)
- `GLM4ToolCallParser`
- `MistralToolCallParser`
- `KimiK2ToolCallParser`
- `PythonicToolCallParser`
- `Llama3ToolCallParser`
- `MiniMaxM2ToolCallParser`
- One file per parser. Each independently testable.

### Phase 5: UI Streaming
- `StreamingUIAdapter`
- Wire cloud path into `EventPipeline`
- Wire local MLX path into same `EventPipeline`
- Remove `StreamingOutputBuffer` tool-text heuristics
- Integration test: streaming text visible in UI from both paths

### Phase 6: Delete Legacy Code
- Remove `ToolCallFallbackParser.swift`
- Remove `StreamingOutputBuffer.swift` heuristic classification
- Remove `clearStreamingBuffer` calls from `ToolLoopHandler`
- Mark all replaced code as `// PHASE 2+` per Cardinal Rule 4
