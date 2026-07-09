# Conversation Stream — Architecture Specification

> Source of truth for the agentic conversation pipeline. Written to prevent regression
> after the rebuild that replaced the mutable `ChatHistoryCoordinator` with an
> append-only, event-sourced conversation log. **If you change the conversation
> pipeline, update this doc.** A change that violates a stated invariant is a bug.

## 1. Problem statement (why this exists)

The previous implementation stored the conversation in a single mutable array
(`ChatHistoryCoordinator.messages`) with mutators `removeDraftMessage`,
`replaceMessage`, `replaceOldestMessages`, `replaceAllMessages`, `updateMessageStatus`.
Observed failures traced to this design:

1. **Cache invalidation / agent slowdown** — the prompt prefix was rewritten every
   turn (truncation, draft finalize, status updates), so provider prefix-caches never
   warmed. Per-turn cost grew without bound → "slower every turn".
2. **Model loses its trail** — non-deterministic ordering (in-memory append timing,
   concurrent tool loop) meant the same logical turn produced different serializations.
3. **UI flicker** — `removeDraftMessage` then `append` swapped the message identity,
   so SwiftUI rows disappeared and reappeared.
4. **Leaked tool output as the answer** — `FinalResponseHandler` collapsed structured
   tool results into a free-text dump (`toolResultsSummaryText` / `compactToolSummaryLines`)
   and surfaced it as the user-facing final message (telemetry: `deliveryStatus: "missing"`,
   content = `"Inspected and analyzed: … Tools run: …"`).

## 2. Design principles (non-negotiable)

- **Append-only is the only write.** Turns are immutable once written. No edit, no
  remove, no reorder, no overwrite. Compaction appends a checkpoint; it never mutates
  existing turns.
- **One writer.** Exactly one type (`ConversationStreamStore`) may append to a session's
  log. Producers emit events; they never touch the log directly.
- **Deterministic read.** Any projection built from the log must be a pure function of
  `(turns in `seq` order)`. Same log ⇒ same projection, byte-for-byte.
- **Protected context.** System prompt and tool definitions are injected at projection
  time, never stored in the journal. They are always first and unchangeable.
- **Session isolation.** Each session is an independent stream. Switching sessions
  moves a pointer; no data is copied or lost. Retention guarantees durability within
  the window.
- **Everyone reads; few write.** Reads are unbounded and cheap (projections). Writes
  are serialized through one actor.

## 3. Architectural layers

Dependency direction is strictly downward; upper layers depend on *protocols* in the
layer below (Dependency Inversion), never on concretes.

```
L1 Presentation / Adapters      SwiftUI, pipeline handlers (FinalResponseHandler, ToolLoopHandler, …)
   │ depends ONLY on ConversationService (protocol)
L2 Application (Mediator)        ConversationCoordinator (actor)
   │ use-cases: startSession, switchSession, submit, commitAgentTurn,
   │            commitToolResult, compact, project(_:)
L3 Ingestion (Producers)  │  Projection (Read models)
   │ TurnProducer impls     │  ConversationProjection impls
L4 Session Registry            SessionRegistry (actor) + SessionRetentionPolicy (Strategy)
   │ wraps SessionManager’s existing currentSessionId / switch
L5 Persistence (Write model)   ConversationStreamStore (actor), NDJSON-backed, seq + ts
   │ implements ConversationLogRepository
L6 Domain Model (zero deps)    Turn, TurnMeta, TurnEvent, Producer, tool summaries
```

## 4. Domain model (L6)

```swift
enum TurnProducer: String, Sendable, Codable, CaseIterable {
    case user, agent, tool, planner, system
}

enum TurnContent: Sendable, Codable {
    case userText(String)
    case assistant(text: String, reasoning: String?, toolCalls: [ToolCallSummary])
    case toolCall(ToolCallSummary)
    case toolResult(ToolResultSummary)
    case systemText(String)
    case plan(String)
    case checkpoint(String)        // compressed summary; never edited, only appended
}

struct TurnMeta: Identifiable, Sendable, Codable {
    let id: UUID
    let seq: UInt64                // monotonic, assigned by the store
    let ts: Date                   // wall-clock, for display/debug
    let producer: TurnProducer
    let sessionId: String
    let conversationId: String
}

struct Turn: Identifiable, Sendable, Codable {
    let meta: TurnMeta
    let content: TurnContent
    var id: UUID { meta.id }
}

struct TurnEvent: Sendable {       // what producers emit; store assigns seq + ts
    let producer: TurnProducer
    let sessionId: String
    let conversationId: String
    let content: TurnContent
}

struct ToolCallSummary: Sendable, Codable {
    let toolCallId: String
    let name: String
    let argumentsDigest: String    // hashed args, never the raw payload in the log head
}

struct ToolResultSummary: Sendable, Codable {
    let toolCallId: String
    let name: String
    let status: String             // "completed" | "failed"
    let targetFile: String?
    let outputRef: String?         // pointer to full payload (envelope) in store, not inline
}
```

**Invariant D1:** `seq` is strictly increasing per session log and is assigned only by
`ConversationStreamStore.append`. No two turns share a `seq`.

## 5. Persistence / write model (L5)

`ConversationStreamStore` is an `actor`. The only mutating operation is `append`.

```swift
protocol ConversationLogRepository: Sendable {
    func append(_ event: TurnEvent) async throws -> Turn
    func allTurns() async -> [Turn]
    func turns(after seq: UInt64) async -> [Turn]
    func latestCheckpoint() async -> Turn?
}

actor ConversationStreamStore: ConversationLogRepository {
    // append-only; assigns seq (counter), ts (Date.now); fsync NDJSON line.
    // reloads existing NDJSON on init to preserve durability across launches.
}
```

Storage: `.ide/chat/<conversationId>/turns.ndjson`, one JSON line per turn, matching the
existing `Logging/ConversationLogStore` durability convention.

**Invariant D2 (append-only):** no API returns a mutating handle to internal state;
`allTurns()` returns a copy. There is no `remove` / `replace` / `update` API.
**Invariant D3 (durability):** a returned `append` is not acknowledged until the line is
fsynced.

## 6. Session isolation + retention (L4)

`SessionRegistry` owns one `ConversationStreamStore` per `sessionId` and wraps
`SessionManager` (existing `currentSessionId`, `switchSession` at
`SessionManager.swift:99/134`). Starting/switching a session changes the active pointer
only.

`SessionRetentionPolicy` is a Strategy:

```swift
protocol SessionRetentionPolicy {
    func shouldRetain(_ session: SessionRecord, now: Date) -> Bool
}
// concretes: TimeBasedRetention(maxAge:), CountBasedRetention(maxCount:)
```

Within the retention window the persisted NDJSON is the durable source ("bank-solid"):
eviction only deletes the file *after* expiry and only for inactive sessions.

**Invariant D4:** switching sessions never alters either stream's turns.
**Invariant D5:** an active session is never evicted.

## 7. Projections / read models (L3)

```swift
protocol ConversationProjection {
    associatedtype Output
    func project(_ turns: [Turn], context: ProjectionContext) -> Output
}
```

Concretes (each SRP: one job):
- `PromptProjector` — LLM messages. Injects `SystemContextProvider` (immutable system
  prompt + tool definitions) at index 0 with a cache breakpoint, then appends turns in
  `seq` order.
- `UIProjector` — SwiftUI view models keyed by immutable `Turn.id` (append-only rows,
  no flicker). Drafts are an *overlay*, never a log turn.
- `TelemetryProjector` — NDJSON events (reuses `Logging/ConversationLogStore`, replacing
  the old side-writer).
- `VectorProjector` — feeds the vector store (replaces `VectorStoreEmbeddingCoordinator`
  buffering).

**Invariant D6 (stable prefix):** because system/tool block is fixed and the log is
append-only, `PromptProjector` output prefix for turns `[0..n]` is identical across
turns → provider prefix-cache stays warm → cost flattens.
**Invariant D7 (protected context):** the system prompt and tool definitions are never
present in any `Turn`; they cannot be reordered or overwritten.

## 8. Ingestion / producers (L3)

```swift
protocol TurnProducer {
    var producer: TurnProducer { get }
    func emit(_ content: TurnContent, conversationId: String, sessionId: String) async
}
```

Concretes emit only: `UserProducer`, `AgentProducer` (model turns), `ToolProducer`
(tool executor), `PlannerProducer`, `SystemProducer`. None read or mutate the log.

`ConversationCoordinator` (Mediator, L2) routes `emit` to the active session's
`ConversationStreamStore.append`. It is the only facade the app/UI/pipeline use, behind the
`ConversationService` protocol (DIP).

## 9. Compaction

`CompactionPolicy` (Strategy) decides when to checkpoint. On trigger,
`PromptProjector`/coordinator appends a `TurnContent.checkpoint(summary)`; subsequent
projections resume from the latest checkpoint. The canonical log is never edited.

```swift
protocol CompactionPolicy {
    func shouldCompact(_ turns: [Turn]) -> Bool
}
// concretes: TokenBudgetCompaction(budget:), TurnCountCompaction(limit:)
```

**Invariant D8:** compaction never removes or rewrites existing turns; it only appends.

## 10. Concurrency & notifications

All stores/coordinators are `actor`s → serialized appends, no scrambling. The EventBus
(`Core/EventBus.swift`) is retained **only** for notifications
(`ConversationAdvancedEvent(sessionId, seq)`); observers (UI, vector, telemetry)
refresh their projection but never mutate the log.

## 11. Design patterns → SOLID

| Pattern | Location | SOLID |
|---|---|---|
| Event Sourcing | `ConversationStreamStore` | SRP: store only writes/orders |
| CQRS | write log vs read projections | SRP + OCP |
| Repository | `ConversationLogRepository` | DIP |
| Strategy | `CompactionPolicy`, `SessionRetentionPolicy` | OCP |
| Mediator | `ConversationCoordinator` | SRP |
| Observer | EventBus `ConversationAdvancedEvent` | decoupling |
| Protocol-oriented / DIP | `ConversationService`, `TurnProducer`, `ConversationProjection` | DIP + ISP |

## 12. Migration (from `ChatHistoryCoordinator`)

1. New subsystem built additive under `osx-ide/Services/Conversation/`; build stays green.
2. Each of the 8 writers (`ConversationManager`, `ToolLoopHandler`, `FinalResponseHandler`,
   `InitialResponseHandler`, `QAReviewHandler`, `ConversationSendCoordinator`,
   `DispatcherNode`, `ConversationFlowGraphFactory`) is migrated behind `ConversationService`.
3. `ChatHistoryCoordinator` and the leaky helpers (`toolResultsSummaryText`,
   `compactToolSummaryLines` as answer, `isGenericStatusMessage` / `isIntermediateExecutionHandoffResponse`
   string gates) are deleted once all writers are moved (boyscout rule: leave no junk).
4. `FinalResponseHandler` emits a structured `{ answer, delivery_state, unresolved }`
   object; on parse failure it returns a neutral fallback — never tool output.

## 13. Regression-prevention test contract

These properties MUST hold and are covered by tests:

- **Append-only:** every `Turn` returned from `allTurns()` is immutable; no `remove`/
  `replace`/`update` API exists on the store.
- **Ordering:** `seq` strictly increases; projection order equals `seq` order.
- **No-overwrite:** appending after reload yields the same turns + new ones, never edits.
- **Durability:** turns survive store teardown + reload (fsync).
- **Session isolation:** turns written to session A are absent from session B; switching
  does not mutate either.
- **Stable prefix:** `PromptProjector` output prefix for turns `[0..n]` is equal across
  two projections that include those turns.
- **Protected context:** system/tool block is always index 0 and identical; no `Turn`
  contains system/tool text.
- **Compaction safety:** after checkpoint, existing turns unchanged; projection resumes
  from checkpoint.
- **Leak prevention:** a final answer derived from a tool-only log never equals a raw
  tool dump; structured `answer` is used, else neutral fallback.

## 14. Build & verification

```sh
./run.sh build      # xcodebuild; must pass after every phase
./run.sh test       # unit tests (ConversationStreamStoreTests, ProjectionTests, …)
```

Every phase is built and tested before the next begins (build-first discipline).
