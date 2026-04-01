# Contextual Inline Completion — Product & Engineering Specification

## Document Status
Draft v1.0

## Purpose

This document specifies the design, architecture, delivery plan, and acceptance criteria for introducing **contextual inline code completion** into `osx-ide` / `ai-ide`.

The goal is to introduce native-feeling, low-latency, ghost-text code suggestions directly inside the editor, with acceptance through keyboard-driven workflows such as `Tab`, while leveraging the project’s existing strengths:

- native macOS editor experience
- layered architecture
- event-driven communication
- actor-based concurrency
- project indexing
- local RAG and code chunk retrieval
- local MLX-based inference and benchmarking direction

This feature is intended to close a major usability gap versus modern AI-enabled IDEs while differentiating through **project-aware suggestions grounded in real application context**, not generic stateless continuations.

---

## Strategic Rationale

Inline completion is not a cosmetic add-on. It is a core interaction loop in AI-native coding environments.

Without it, users must break flow by switching from active typing into explicit prompt-based interaction. With it, the IDE becomes proactive, ambient, and materially faster to work in.

The strategic opportunity for `ai-ide` is not merely to match competitors with ghost-text completion, but to surpass them by using local code intelligence and selective RAG enrichment to suggest code that reflects the actual architecture, symbols, conventions, and implementation patterns of the current project.

This matters because many existing AI IDEs produce syntactically plausible suggestions that are detached from the structure of the application. When suggestions ignore project context, they often become noise. If `ai-ide` can make inline suggestions aware of the codebase while preserving the speed and polish of a native editor, the feature can become a clear source of user delight and differentiation.

---

## Product Objective

Deliver **contextual inline code completion** that:

- appears as ghost text directly in the editor
- is keyboard-first and non-intrusive
- feels native and low-latency
- prioritizes immediate local context
- selectively enriches with project-aware retrieval
- can use local inference where appropriate
- never compromises editor responsiveness

---

## Non-Goals

This feature is not intended to:

- replace full chat or agent-based generation
- perform autonomous multi-file editing
- rewrite large portions of code without explicit user action
- act as a generic “AI everywhere” layer on each keystroke
- run the full chat/RAG orchestration pipeline for inline suggestions
- become a full decisioning engine for refactoring or architecture advice

This feature is a **real-time completion subsystem**, not a miniaturized version of the broader assistant.

---

## User Experience Goals

The feature should feel like a natural extension of typing.

The user types normally. After a short pause, the IDE may show a dimmed inline suggestion at the caret position. If the user wants it, they press `Tab` to accept it. If they do not want it, they keep typing or dismiss it with `Esc`.

The feature should be:

- helpful more often than distracting
- quiet rather than noisy
- local in spirit rather than theatrical
- stable rather than flickery
- precise rather than verbose

### Desired UX Characteristics

- Suggestions appear only when confidence is sufficient.
- The editor remains responsive even under indexing or inference load.
- Suggestions prefer short, likely continuations over grand speculative insertions.
- The user always stays in control.
- No document mutation happens until explicit acceptance.
- Suggestions are easy to dismiss and easy to trust.

---

## Core Functional Requirements

### Inline Suggestion Presentation
- Show ghost-text suggestions directly inline in the editor at the current caret position.
- Suggestions must be visually distinct from committed document content.
- Suggestions must not alter the underlying buffer until accepted.

### Acceptance & Dismissal
- `Tab` accepts the current suggestion.
- `Esc` dismisses the current suggestion.
- Continued typing should naturally replace or invalidate the suggestion.
- Optional support should exist for partial acceptance and cycling between alternatives in later phases.

### Triggering
- Suggestions may appear automatically after a configurable idle debounce.
- Suggestions may also be explicitly triggered via a keyboard shortcut.
- Suggestions must not trigger aggressively during continuous rapid typing.

### Context Awareness
- Immediate local context must always be considered.
- Project-aware retrieval may be used selectively when beneficial.
- Suggestions should reflect available symbols, nearby code, and project patterns where possible.

### Execution Modes
- Support local inference.
- Support optional remote fallback.
- Support hybrid routing policies.
- Preserve the ability to disable remote completion entirely.

### Cancellation
- Every in-flight completion request must be cancellable.
- Cursor movement, edits, file switches, or selection changes must invalidate old work immediately.

### Telemetry
- Record suggestion latency, presentation count, acceptance, dismissal, and source path.
- Telemetry must support tuning without degrading privacy posture.

---

## Non-Functional Requirements

### Performance
- The editor must remain responsive under all conditions.
- Completion generation must be bounded by strict latency budgets.
- Retrieval must be cached and bounded.
- Long-running or slow inference must degrade gracefully.

### Stability
- The feature must never corrupt the editor buffer.
- Ghost rendering must be presentation-only until acceptance.
- Completion state must not leak across files or stale cursor positions.

### Maintainability
- The subsystem must remain separate from the full chat and agent orchestration flow.
- Prompt construction, retrieval, ranking, rendering, and acceptance should be cleanly separated.
- Architecture should support future model routing changes without forcing editor rewrites.

### Trust
- Users must be able to understand when suggestions are local-only, hybrid, or using remote providers.
- Settings should make behavior explicit and controllable.
- The feature must fail silent under adverse conditions rather than degrade the core editing experience.

---

## Architectural Positioning

The repository README describes a layered architecture with UI, Service, Core, and Data layers, plus event-driven communication, actor-based concurrency, modular language support, indexing, and database-backed persistence.

This feature should fit that structure cleanly.

### Proposed Placement by Layer

#### UI Layer
Responsible for ghost-text rendering, keyboard interactions, editor state observation, and inline suggestion display behavior.

#### Service Layer
Responsible for orchestration of inline completion requests, debouncing and cancellation, routing to local/remote inference, context assembly, suggestion ranking, and telemetry coordination.

#### Core Layer
Responsible for protocols, request/response models, ranking utilities, prompt-shaping helpers, cancellation identifiers, feature policy interfaces, and completion result semantics.

#### Data Layer
Responsible for code chunk retrieval, symbol lookup, project index access, caching, persistence of settings, and telemetry storage if persisted locally.

---

## High-Level Architectural Principle

**Inline completion must be implemented as a dedicated low-latency subsystem, not as a repurposed chat request path.**

This is the most important design rule in the entire feature.

---

## Proposed Subsystem

### `InlineCompletionEngine`

This subsystem is the main coordinator for inline completion requests. It should live in the Service Layer and orchestrate the following specialized components.

#### Responsibilities
- receive editor signals
- apply debounce and trigger policy
- issue cancellable requests
- assemble minimal context
- invoke retrieval when justified
- request model inference
- rank or reject results
- publish suggestion updates
- emit telemetry

---

## Proposed Components

### 1. `EditorSignalBridge`
Captures editor state and transforms it into completion-ready signals.

### 2. `CompletionTriggerPolicy`
Decides whether a suggestion request should start.

### 3. `CompletionContextAssembler`
Builds compact, completion-specific context.

### 4. `CompletionRetrievalLayer`
Provides fast, bounded project-aware context retrieval.

### 5. `CompletionInferenceService`
Routes requests to the chosen inference backend.

### 6. `SuggestionRanker`
Filters and ranks candidate suggestions.

### 7. `GhostTextRenderer`
Displays suggestion content inline without mutating the buffer.

### 8. `CompletionTelemetryService`
Captures performance and usefulness signals.

---

## Context Strategy

### Context Priority Order

#### Tier 1 — Immediate Local Context
Always highest priority.

#### Tier 2 — Symbol Context
Used when the current location references known abstractions.

#### Tier 3 — Project-Aware Retrieval
Used selectively.

#### Tier 4 — Global Project Priors
Optional and lightweight.

### Key Rule
Project-aware retrieval must enrich the completion request, not dominate it.

---

## Model Strategy

Inline completion should not use the same prompt shape, token budget, or response style as chat mode.

### Routing Modes
- Local Only
- Remote Only
- Hybrid Preferred Local
- Hybrid Preferred Remote

### Recommendation
For automatic inline completion, prefer smaller, faster local models, highly compact prompts, low token budgets, and warmed model sessions where feasible.

---

## UX Specification

### Triggering
- Automatic trigger after configurable idle debounce.
- Manual trigger via keyboard shortcut.
- No suggestions while actively selecting text.
- No suggestions during IME composition.

### Display
- One primary suggestion shown by default.
- Rendered inline as ghost text.
- No automatic popover unless explicitly requested.

### Acceptance
- `Tab` accepts the whole suggestion.
- `Esc` dismisses current suggestion.

### User Controls
Settings should include enable/disable, routing mode, aggressiveness, retrieval toggle, max suggestion length, multiline enablement, and debug visibility.

---

## Performance Budget

### Target Latency
- ideal perception target: 50–150 ms after pause
- acceptable upper bound for automatic suggestions: ~250 ms
- sustained latency above ~400 ms is not acceptable for inline completion

### Graceful Degradation
When latency budgets are exceeded repeatedly:
- reduce retrieval usage
- reduce suggestion length
- increase debounce
- prefer local-only mode
- suppress suggestions if needed

---

## Proposed Phases

# Phase 1 — Editor Integration Spine
- inline engine
- signal bridge
- ghost renderer
- debounce and cancellation
- single suggestion only
- `Tab` / `Esc`

# Phase 2 — Local Intelligence & Ranking
- richer local context
- symbol awareness
- ranking and rejection filters
- telemetry
- latency benchmark harness

# Phase 3 — Selective RAG Enrichment
- completion retrieval layer
- same-file and symbol-priority retrieval
- bounded semantic top-K retrieval
- retrieval caching and gating

# Phase 4 — Product Polish & Alternatives
- alternatives
- partial acceptance
- settings surface
- advanced telemetry and debug overlay

---

## Detailed Engineering Task Breakdown

### Workstream A — Editor Integration
### Workstream B — Triggering & Cancellation
### Workstream C — Context Assembly
### Workstream D — Retrieval
### Workstream E — Inference Routing
### Workstream F — Ranking & Filters
### Workstream G — Telemetry & Benchmarking
### Workstream H — Settings & Controls

---

## Rollout Strategy

### Internal Rollout
- behind feature flag
- enabled in development builds first
- benchmark and telemetry-driven tuning

### Controlled User Rollout
- opt-in beta setting
- default conservative aggressiveness

### General Availability Conditions
- stable editor responsiveness
- acceptable latency profile
- healthy acceptance metrics
- no significant report pattern of flicker or corruption

---

## Recommended Initial Defaults

- inline completion: enabled only in dev/beta initially
- completion aggressiveness: conservative
- retrieval: enabled selectively
- remote fallback: disabled by default for automatic suggestions
- multiline suggestions: disabled initially except explicit/manual trigger
- alternatives: off initially

---

## Delivery Recommendation

Proceed now.

This feature is important enough to justify immediate investment because it is not opportunistic scope creep. It is a core capability expected in an AI-native IDE, and it aligns strongly with the product’s existing architecture and technical direction.

The correct mindset is:

> Build the fastest trustworthy version first.  
> Then make it smarter.  
> Then make it richer.
