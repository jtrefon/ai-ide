# Codebase Review — OSX IDE

## Summary of Issues (ranked by impact)

### 1. Monster Files — Maintainability Crisis

The three largest files exceed reasonable size by an order of magnitude:

| File | Lines | Problem |
|------|-------|---------|
| `Services/CloudPipeline/ToolLoopHandler.swift` | **2,775** | Entire tool-loop scheduling: repetition detection, recovery logic, mutation guarding, recursive dispatch |
| `Services/LocalModels/LocalModelProcessAIService.swift` | **1,964** | Model loading, inference, memory management, KV cache quantization, budget calculation |
| `Services/OpenRouterAI/OpenRouterAIService.swift` | **1,431** | Chat preparation, message mapping, logging, types |

**11 more files exceed 500 lines**: ChatPromptBuilder (1,006), ConversationManager (932), AIToolExecutor+Execution (884), ContentView (627), FinalResponseHandler (572), TerminalTools (644), ToolArgumentResolver (543), LocalModelFileStore (539), ModernFileTreeCoordinator (536), LanguageKeywordRepository (687).

**Impact**: Code reviews are impossible at this size. Single-responsibility violations are guaranteed. Bugs hide in plain sight.

---

### 2. MainActor.run Busy-Loop — Potential Deadlock

In `DependencyContainer.swift`, `initializeHeavyServices` runs a polling loop:

```swift
while true {
    let done = await MainActor.run { !_projectCoordinator.isInitializing }
    if done { break }
    try? await Task.sleep(nanoseconds: 100_000_000)
}
```

12 `MainActor.run` hops from a background task. If the coordinator takes long to initialize, closures pile up. Should use `AsyncStream` / signal-based handoff instead of polling.

---

### 3. 28 Singletons — Hidden Dependencies, Poor Testability

Notable singletons:
- `AgentActivityCoordinator.shared`
- `ConversationPlanStore.shared`
- `CheckpointManager.shared`
- `IndexLogger.shared`
- `ToolTimeoutCenter.shared`
- `ToolExecutionTelemetry.shared`
- `GoogleWebSearchEngine.shared`
- `DiagnosticsLogger.shared`
- And ~20 more.

**Impact**: Tests cannot isolate. Order-dependent failures. Global mutable state hides data races.

---

### 4. 50+ Force Unwraps — Preventable Crashes

Widespread `!` usage across the codebase. Services layer is highest risk (total feature loss on crash). Already documented in REFOCUS_TRACKER as Phase 5.5 — not started.

---

### 5. Fire-and-Forget Task { } — Silently Swallowed Errors

Multiple `Task { await ... }` calls without error handling:
- `Task { await coordinator.stop() }` — failure silently lost
- `Task { await modelSearch.loadModels() }` — failure silently lost
- Many more in views: `Task { await triggerSearch() }`, `Task { await refreshResults() }`

---

### 6. Direct NSApp References — Block Unit Tests

20+ direct calls to `NSApplication.shared` (`NSApp`) in services and views. Any code touching `NSApp` cannot run in XCTest. Should route through `WindowProvider` / `ApplicationProxy` protocols.

---

### 7. Test Quality — Inconsistent setUp, Missing Expectations

- Mix of sync `setUp()` and async `setUp() async throws` across test files
- Only 5 of 79 test files use `XCTestExpectation` — async tests rely on `Task.sleep` instead of proper fulfillment
- Source: 57,708 lines / Test: 12,989 lines (~22% coverage ratio)

---

### 8. Build Database Locked — CI / Dev Flow Broken

`database is locked` error from concurrent `xcodebuild` invocations colliding on the same DerivedData. Need clean build isolation.

---

## Architectural Gaps

These emerged during the review and relate to Issue #1 (Tool / Agent architecture):

1. **No formal tool registry** — Tools are assembled ad-hoc in `ConversationToolProvider`. No central registry that defines capabilities, required permissions, schema.
2. **No scope/permission model** — Tools run with whatever access the process has. No per-tool sandboxing or path scoping.
3. **Single protocol** (`AITool`) handles everything — prompt generation, execution, schema, error recovery. No separation of concerns.
4. **Mode enforcement is fragile** — Read-only vs. agent mode is enforced by a boolean check in `ToolLoopHandler` and runtime classification (`isMutationToolName`), not by tool metadata.
5. **No formal adapters for model types** — Local (Gemma) and cloud (OpenRouter) models have different tool-call formats, handled by ad-hoc conditionals.
