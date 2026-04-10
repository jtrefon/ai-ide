# Contextual Inline Completion — Technical Implementation Blueprint

## Purpose

This document translates the product spec into concrete engineering direction aligned with the existing ai-ide architecture.

It defines:
- module boundaries
- suggested class/protocol structure
- data flow contracts
- PR slicing strategy

---

## Module Placement

Recommended folder structure:

```
Services/InlineCompletion/
    InlineCompletionEngine.swift
    CompletionTriggerPolicy.swift
    CompletionContextAssembler.swift
    CompletionInferenceService.swift
    SuggestionRanker.swift
    CompletionTelemetryService.swift

Core/Completion/
    Models/
        InlineCompletionRequest.swift
        InlineCompletionResult.swift
        InlineSuggestionCandidate.swift
    Protocols/
        CompletionProvider.swift
        CompletionRetrievalProvider.swift

Data/Completion/
    CompletionRetrievalLayer.swift
    CompletionCache.swift

UI/Editor/
    GhostTextRenderer.swift
    EditorSignalBridge.swift
```

---

## Core Contracts

### InlineCompletionRequest

Contains:
- filePath
- language
- prefix
- suffix
- cursorPosition
- scopeSummary
- symbols
- retrievalContext (optional)
- requestId

### InlineCompletionResult

Contains:
- suggestionText
- confidenceScore
- source (local / remote / hybrid)
- latency

### InlineSuggestionCandidate

Used internally for ranking.

---

## Engine Flow

```
EditorSignalBridge
    → CompletionTriggerPolicy
        → InlineCompletionEngine
            → CompletionContextAssembler
                → CompletionRetrievalLayer (optional)
                    → CompletionInferenceService
                        → SuggestionRanker
                            → GhostTextRenderer
```

---

## Cancellation Strategy

Every request carries:

```
requestId: UUID
```

Engine keeps:

```
currentActiveRequestId
```

If mismatch → discard result.

---

## Debounce Strategy

Initial suggestion:

```
120–200ms idle debounce
```

Dynamic adjustment:
- increase debounce after rapid typing
- reduce debounce after idle

---

## Retrieval Strategy

### Phase 1
Disabled.

### Phase 2
Same-file + symbol lookup.

### Phase 3
Top-K semantic retrieval:

```
K = 2–3
maxTokensInjected = strict cap
```

---

## Prompt Template (Simplified)

```
Language: Swift
File: path

Context:
[prefix]

Cursor

[suffix]

Instruction:
Continue the code naturally. Do not explain.
```

---

## Ranking Heuristics

Reject if:
- duplicates suffix
- breaks indentation
- exceeds max length
- low confidence

Prefer:
- minimal extension
- syntactically clean
- aligned with scope

---

## Rendering Strategy

Ghost text:
- attributed string overlay
- no mutation of NSTextStorage
- redraw on cursor move or invalidation

---

## PR Plan

### PR 1
- EditorSignalBridge
- GhostTextRenderer

### PR 2
- InlineCompletionEngine (no RAG)
- debounce + cancellation

### PR 3
- local inference integration
- basic ranking

### PR 4
- telemetry + benchmark harness

### PR 5
- retrieval layer (same-file + symbol)

### PR 6
- semantic retrieval

### PR 7
- alternatives + polish

---

## Testing Strategy

- unit tests for ranking
- integration tests for cancellation
- performance tests for latency
- editor interaction tests

---

## Key Principle

> Completion must feel instant before it feels intelligent.

---

## Final Note

This blueprint is intentionally conservative in early phases to protect editor responsiveness.

Once stable, intelligence can be layered safely.
