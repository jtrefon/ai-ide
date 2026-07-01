# FIM Code Completion — Fix Plan

Date: 2026-07-01
Source: Code review of the inline completion / FIM pipeline.

---

## P0 — Correctness Bugs (must fix)

### 1. Broken cancel chain in FIMInferenceService

**File:** `Services/LocalModels/FIMInferenceService.swift:126-133`

**Problem:** `generateStream()` creates the real MLX generation `task`, then wraps it in
`generationTask = Task { await task.value }`. When the stream consumer cancels,
`onTermination` calls `generationTask?.cancel()` — but this only cancels the wrapper,
not the real `task`. The MLX model keeps generating tokens until `maxTokens` is exhausted.
Every keystroke that abandons a stream leaks inference work.

**Fix:** Set `generationTask = task` directly. `onTermination` then cancels the real task;
the `Task.isCancelled` check inside the generation loop (line 116) breaks cleanly.
`unload()` already calls `generationTask?.cancel()`, so it also works correctly.

---

### 2. FIMInferenceService memory leak on model switch

**File:** `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:216-223`

**Problem:** `resolveFIMService` overwrites `fimService` with a new actor instance without
calling `unload()` on the old one. The old actor still holds `modelContainer` (the loaded
MLX model, ~1-3 GB RAM) and its `generationTask`. Model weights leak on every model switch.

**Fix:** Call `await fimService?.unload()` before assigning the new service.

```swift
await fimService?.unload()
let service = try await FIMInferenceService(modelId: modelId)
fimService = service
```

---

### 3. No prefix/suffix truncation to fit context window

**File:** `Services/LocalModels/FIMInferenceService.swift:91-96`

**Problem:** The FIM prompt is constructed by concatenating prefix + suffix verbatim.
The context window is 4096 tokens (`maxKVSize`) but `CompletionContextAssembler` can
return 4000 chars of prefix + 1200 chars of suffix. In dense code, this can exceed
4096 tokens after tokenization, causing undefined MLX behavior.

**Fix:** After encoding the full prompt, if token count exceeds available budget
(`maxKVSize - maxTokens - reservation`), truncate prefix and suffix proportionally
and re-encode. The prompt construction should be:

1. Tokenize prefix and suffix separately to get token counts
2. If total exceeds budget, trim each proportionally in character space
3. Reconstruct prompt with truncated text

---

### 4. Broken FIMTokenBridge.applyChatTemplate

**File:** `Services/LocalModels/FIMInferenceService.swift:45-48`

**Problem:** `applyChatTemplate` concatenates all message contents with `\n`, discarding
roles and the Jinja template entirely. The FIM path never calls this method, but if MLX
ever calls it internally (token counting, config validation, etc.), it produces garbage.

**Fix:** Replace with a throwing implementation:

```swift
func applyChatTemplate(messages: [[String: any Sendable]], ...) throws -> [Int] {
    throw AppError.aiServiceError("chat template not supported for FIM models")
}
```

---

## P1 — Architecture & Performance (should fix)

### 5. Dual routing logic

**Files:**
- `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:267-303`
- `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:57-131`

**Problem:** Two layers implement routing independently. `CompletionInferenceService`
dispatches to local (FIM) vs remote with fallback logic. Then `AIServiceInlineCompletionProvider.complete()`
re-dispatches with different fallback logic. "Local" in one layer means FIM; in the other
it means the full chat model. This works by accident today but is fragile.

**Fix:** Strip all fallback/hybrid logic from `AIServiceInlineCompletionProvider.complete()`.
Make it a pure executor that only handles `.remoteOnly` and `.localOnly` without fallback.
`CompletionInferenceService` becomes the single routing authority for all four modes.

---

### 6. Inference not cancellation-aware

**Files:**
- `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:242-323`
- `Services/LocalModels/FIMInferenceService.swift:68-74`

**Problem:** The engine cancels the outer `Task` on new keystroke, but `infer()`,
`completeLocally()`, and `generate()` don't check `Task.isCancelled` during the call.
The underlying FIM generation runs to completion (up to 512 tokens) before the
cancellation is noticed at the next `Task.isCancelled` check in the engine.

**Fix:** Add `try Task.checkCancellation()` or equivalent checks at key points in the
inference chain:
- At the start of `CompletionInferenceService.infer()`
- At the start of `AIServiceInlineCompletionProvider.completeLocally()`
- In `FIMInferenceService.generate()` after each stream chunk

---

### 7. First completion is always slow — no eager model loading

**File:** `Services/LocalModels/FIMInferenceService.swift:51-59`

**Problem:** `ensureLoaded()` is called lazily on the first `generateStream()` call.
A 1.5B model takes 1-3 seconds to load. The user's first keystroke in any session
(or after model reload) triggers this inline, blocking the completion.

**Fix:** Add a `prewarm()` method to `FIMInferenceService` that eagerly loads the model.
Call it when `InlineCompletionEngine` initializes or when the first editor pane opens.
The method should be safe to call multiple times (idempotent).

---

### 8. maxSuggestionLength units mismatch

**Files:**
- `Core/Completion/InlineCompletionModels.swift:32`
- `Services/LocalModels/FIMInferenceService.swift:100`
- `Services/LocalPipeline/InlineCompletion/SuggestionRanker.swift:36`

**Problem:** `maxSuggestionLength` (characters) is passed to FIM as `maxTokens` (tokens).
40 characters can be 5-40 tokens depending on the language. The ranker then rejects
anything over 40 characters, wasting generation budget. Conversely, a valid 45-character
completion that fits in 40 tokens is silently rejected.

**Fix:** Add a `maxTokens` field to `InlineCompletionRequest` (initialized based on
`maxSuggestionLength` with a reasonable token/char ratio, e.g. `min(maxSuggestionLength, 40)`).
FIM uses `maxTokens` for generation; the ranker keeps the character-based `maxSuggestionLength`
for display filtering.

---

### 9. Missing languages in trigger policy

**File:** `Services/LocalPipeline/InlineCompletion/CompletionTriggerPolicy.swift:10-14`

**Problem:** 15+ major languages are absent from `supportedLanguages`: Rust, Go, Java,
Kotlin, Ruby, Scala, PHP, Dart, Lua, R, Perl, Haskell, Julia, Zig, C#. Users of these
languages get zero automatic completions with no visible feedback. Manual trigger works
but most users won't discover it.

**Fix:** Add all common languages to the set. Consider making the list configurable via
settings, or removing the allowlist entirely and relying on the editor's language identifier.

---

## P2 — Quality of Life & Polish

### 10. Default context limits too conservative

**File:** `Services/LocalPipeline/InlineCompletion/CompletionContextAssembler.swift:16-18`

**Problem:** Default is `.fast` limits (500 prefix chars, 300 suffix chars).
Qwen2.5-Coder has 32K context. 97% of available context is discarded.

**Fix:** Change default to `.standard` (4000 prefix, 1200 suffix). Keep `.fast` as a
degraded-mode fallback used when telemetry reports persistent slow completions.

---

### 11. No timeout on remote inference

**File:** `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:326-345`

**Problem:** `attemptRemote` has no timeout. Network hang blocks the completion slot
indefinitely. User sees nothing until the OS kills the connection.

**Fix:** Wrap the remote call in `withTimeout(seconds: 10)` using `Task` timeout.

---

### 12. Unused confidenceScore plumbing

**Files:**
- `Services/LocalPipeline/InlineCompletion/CompletionInferenceService.swift:261`
- `Services/LocalPipeline/InlineCompletion/SuggestionRanker.swift:38`

**Problem:** `confidenceScore` is hardcoded to 0.5 and then overridden by
`max(aggressiveness, 0.5)`. The entire confidence system is a no-op.

**Fix:** Either wire real per-token confidence from the model's output distribution,
or remove the confidence field from the result/presentation types.

---

### 13. Cache key uses coarse cursor bucket

**File:** `Services/LocalPipeline/InlineCompletion/CompletionRetrievalLayer.swift:68`

**Problem:** Cache key uses `cursorPosition / 20`, causing stale results within the
same 20-character bucket. Moving from column 19→20 busts the cache unnecessarily.

**Fix:** Use exact `cursorPosition` in the cache key. The 20-second TTL already
prevents unbounded staleness.

---

### 14. Telemetry workload reduction too sensitive

**File:** `Services/LocalPipeline/InlineCompletion/CompletionTelemetryService.swift:35-37`

**Problem:** `shouldReduceWorkload` fires after only 2 completions over 400ms.
Transient slowness (CPU spike, GC pause) immediately degrades the experience.

**Fix:** Increase threshold to 4 slow completions out of the last 6, or use
median latency instead of a count.

---

### 15. Missing test coverage

**Files:** All test files under `osx-ideTests/`

**Problem:**
- `InlineCompletionEngineTests` uses fragile `Task.sleep` for timing
- `CompletionContextAssemblerTests` has only 1 test
- `SuggestionRankerTests` misses edge cases (empty, unicode, keywords)
- No tests for cancellation behavior
- No tests for prefix/suffix truncation
- No tests for FIM token bridge

**Fix:** Replace sleep-based sync with `XCTestExpectation`. Add targeted tests for
each P0/P1 fix.

---

## Execution Order

```
Phase 1 (P0):  #1 → #2 → #3 → #4   (independent, can be done in parallel)
Phase 2 (P1a): #5                    (architectural, unblocks #6)
Phase 3 (P1b): #6 → #7 → #8         (all touch the FIM call path)
Phase 4 (P1c): #9                    (narrow scope, independent)
Phase 5 (P2):  #10 → #11 → #12 → #13 → #14 → #15
```
