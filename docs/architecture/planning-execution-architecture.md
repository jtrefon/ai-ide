# Planning & Execution Architecture

## Philosophy

The current approach — inject the entire plan, let the model self-manage — fails because:

1. **Context dilution**: The plan takes up tokens, and as the conversation grows, the plan gets compressed/garbled
2. **Loss of focus**: The model sees ALL tasks at once and jumps ahead, repeats, or forgets where it is
3. **No anchor**: After context compression, the model can't reliably recover what was done vs what remains
4. **Domain blindness**: The plan structure assumes coding tasks — but the same system must handle architecture, research, refactoring, analysis, and design

**The fix**: Instead of dumping the entire plan into context, the framework manages the plan and feeds **one task at a time**. The model focuses on ONE thing, delivers it, calls `finishTask`, and the framework injects the next.

### Design Principles

1. **Domain agnostic** — The structure must work for ANY goal: architectural design, code implementation, security audit, performance analysis, research investigation, legacy migration. The framework does not assume "files" or "code." The model fills in the domain-specific details.

2. **Model-chosen, not enforced** — The model opts in by calling `plan.init`. Once opted in, the tool's responses guide the model through phases, but there is no pipeline enforcement. The model commits to the plan through tool contract, not system gates.

3. **Value-driven** — Each task carries not just WHAT to do, but WHY it matters and WHAT VALUE it delivers. This keeps the model grounded in purpose, not just mechanical execution.

4. **Maximum focus** — The model sees ONE task at a time. No context wandering, no premature optimization, no task skipping.

5. **Context survival** — Each task's summary is a permanent record. After compression, the model can fully reorient from the current task context alone.

6. **Final synthesis** — After all tasks complete, the model provides a final summary using its own recorded summaries.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      FRAMEWORK (MANAGER)                               │
│                                                                         │
│  ┌──────────────────────┐    ┌────────────────────┐                    │
│  │ ConversationPlanStore│    │   PlanTool (AITool)│                    │
│  │ (persisted JSON)     │◄───│                    │                    │
│  │                      │    │ init / finishTask  │                    │
│  │                      │    │ raiseQuestion      │                    │
│  │                      │    │ breakOutCantContinue│                   │
│  └──────────────────────┘    └────────────────────┘                    │
│         │                           │                                  │
│         ▼                           ▼                                  │
│  ┌──────────────────────────────────────────────────────┐              │
│  │               Phase Guidance (injected by tool)       │              │
│  │  plan_research.md → on init                           │              │
│  │  plan_execution.md → on finishTask transition          │              │
│  └──────────────────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

### The Three-Phase Flow

```
init ──► Research Phase ──► finishTask ──► Execution Phase ──► finishTask ──► All Done
              │                                │
              │ (all tools available)          │ (one task at a time)
              ▼                                ▼
        read_file, search,               read_file, write_file,
        web_browse, grep...              patch_file, run_command...
```

---

## The `plan` Tool

### Actions

| Action | When | What happens |
|--------|------|-------------|
| `init` | Any time | Enters research phase. No summary needed — context comes from the conversation. |
| `finishTask` | End of research or task completion | Research → execution: agent provides task breakdown in summary. Execution → next: marks task done, injects next task context. |
| `raiseQuestion` | Mid-plan | Returns `status: question` with the query. Framework pauses for user input. |
| `breakOutCantContinue` | Stuck | Aborts plan with reason. All remaining tasks marked blocked. |

### Parameters

- **action** (required): `"init"` | `"finishTask"` | `"raiseQuestion"` | `"breakOutCantContinue"`
- **summary** (optional): For finishTask. During research: proposed task breakdown (each task on a new line). During execution: what was done, files changed, verification result.
- **question** (optional): Required for raiseQuestion.
- **blocker_reason** (optional): Required for breakOutCantContinue.

### Output Format

All responses return a ToolFeedback envelope:

```text
status: success | blocked | question | error
message: "Human-readable description"
content:
  action: "finishTask"
  phase: "researching" | "executing"
  task: "Description of current task" (execution phase only)
  purpose: "Why this matters" (execution phase only)
  done_criteria: "How to verify" (execution phase only)
  progress: "2/5" (execution phase only)
  all_done: true (last task only)
```

### Tool Prompt (`plan.md`)

Loaded into system prompt as a concise reference:

- **Purpose**: Break down complex work into structured tasks. Call `init` to opt in.
- **When to Use**: Multi-step tasks needing focus and structure.
- **Available Methods**: Table of init/finishTask/raiseQuestion/breakOutCantContinue.
- **Parameters**: Quick reference only. Phase-specific guidance is injected by tool responses at the right moment.

### Phase Prompts (loaded by tool, NOT in system prompt)

- **`plan_research.md`**: Injected when `init` is called. Tells the model to research using all tools, then call `finishTask` with its task breakdown.
- **`plan_execution.md`**: Injected when `finishTask` transitions to execution. Tells the model to work on the current task and call `finishTask` when complete.

---

## The Three Phases in Detail

### Phase 1: Research

Triggered by `plan(action: "init")`.

The model enters research mode. It uses all available tools (read_file, search_project, web_search, web_browse, run_command, grep, find_file) to explore the codebase, understand the problem, and gather context.

The research prompt tells the model:

> Your ONLY next step is to call `plan(action: "finishTask", summary: "...")` with your proposed task breakdown. You cannot skip this — the plan does not advance until you call finishTask.

The model's summary becomes the task breakdown. Each line becomes a task item.

### Phase 2: Plan → Execution Transition

Triggered by `plan(action: "finishTask", summary: "...")` during research.

The tool parses the summary into plan items (one per line), stores them in `ConversationPlanStore`, and returns the execution phase prompt with the first task's context.

### Phase 3: Task-by-Task Execution

Triggered by the execution phase prompt after transition.

The model works on one task at a time. Each task has:
- **description**: What to do
- **purpose**: Why it matters
- **done_criteria**: How to verify completion
- **progress**: "2/5" showing current position

The model calls `plan(action: "finishTask", summary: "...")` when the task is complete. The tool:
1. Marks the current task complete with the summary
2. Advances to the next pending task
3. Returns the next task's context

When the last task is complete, the tool returns `all_done: true` and asks for a final summary.

### Circuit Breakers

At any phase, the model can:

- `raiseQuestion(question: "...")` — "I need clarification." Returns `status: question`. Framework pauses for user input.
- `breakOutCantContinue(summary: "...", blocker_reason: "...")` — "This cannot be done." Returns `status: blocked`. Plan is terminated, remaining tasks marked blocked.

---

## Data Structures

### TaskPlan (Persisted, survives compression)

```swift
struct TaskPlan: Codable, Sendable {
    let id: String              // UUID — links plan to conversation
    let goal: String            // Single sentence: WHAT we're achieving
    let value: String           // WHY this matters — what success looks like
    let domain: Domain          // The domain of work
    let mode: AIMode            // coder or agent
    let items: [PlanItem]       // Ordered list of all tasks
    let createdAt: Date
    var completedAt: Date?
    var currentIndex: Int       // Which item the model is working on
    var isComplete: Bool        // All items done or blocked
}
```

### PlanItem (One unit of work)

```swift
struct PlanItem: Codable, Sendable {
    let id: String
    let description: String          // WHAT to do
    let purpose: String              // WHY this exists
    let context: [String]            // WHERE/WHAT — relevant files, URLs, concepts
    let doneCriteria: String         // HOW to verify completion
    var status: ItemStatus           // pending | active | completed | blocked
    var summary: String?             // Model's finishTask summary when done
    var blockedReason: String?       // If status == blocked
}

enum ItemStatus: String, Codable, Sendable {
    case pending
    case active
    case completed
    case blocked
}
```

### ConversationPlanStore

Actor-based store with JSON persistence. Provides:

- `getPlan(conversationId:)` — Fetch current plan
- `setPlan(conversationId:plan:)` — Save plan
- LRU cache with `maxEntries` limit
- Legacy string-based API for backward compatibility

---

## Context Injection Flow

### What the Model Sees at Each Step

**After `init` (research phase):**
```
Planning mode. Research the problem using all available tools —
read files, search the codebase, browse the web, run commands.
Understand the current state. When you have a clear plan,
call finishTask with your proposed task breakdown.
```

**After `finishTask` (execution phase begins):**
```
Plan locked. 3 tasks defined. Starting execution.

Current task: Analyze current persistence code
Purpose: Must understand existing implementation
Done when: All persistence-related files have been read and understood
Progress: 0/3

Work on this task. When complete, call finishTask.
```

**After each `finishTask` during execution:**
```
Well done. Task 1/3 complete. Now working on task 2.

Current task: Design repository protocol
Purpose: Repository interface decouples data access from business logic
Done when: Protocol compiles with CRUD method signatures
Progress: 1/3
```

**After final `finishTask`:**
```
All 3 tasks complete. Provide a final summary.

Summary:
  - Task 1: Analyzed existing code ...
  - Task 2: Designed protocol ...
  - Task 3: Implemented repository ...
```

### What Survives Context Compression

After compression, only these elements are re-injected:
1. The **goal** (one sentence)
2. The **current task** (with purpose, done criteria)
3. The **completed tasks list** (id + summary only)
4. The **last tool result or error**

This is roughly 1/10th of the full plan. The model can fully reorient from this.

---

## Artifact Detector Integration

The framework has a `hasOutstandingRequestedArtifacts` check that parses the user's input for file paths and verifies they've been created on disk. This is a safety net for non-plan sessions.

When a plan is active, the artifact detector defers to the plan. In `ToolLoopHandler.swift`, the `requested_artifacts_completed` path checks:

```swift
let planStillActive = await ConversationPlanStore.shared
    .getPlan(conversationId: conversationId)
    .map { !$0.isComplete } ?? false

if !planStillActive {
    // only then: log artifacts completed and force final response
}
```

This prevents the artifact detector from ending the session while plan tasks remain.

---

## Implementation Status

| Component | File | Status |
|-----------|------|--------|
| TaskPlan types | `Services/Planning/TaskPlan.swift` | ✅ Done |
| ConversationPlanStore | `Services/Planning/ConversationPlanStore.swift` | ✅ Done |
| PlanTool (init/finishTask/raiseQuestion/breakOutCantContinue) | `Services/Planning/PlanTool.swift` | ✅ Done |
| Tool prompt (concise reference) | `Prompts/Tools/v2/plan.md` | ✅ Done |
| Research phase prompt | `Prompts/Tools/v2/plan_research.md` | ✅ Done |
| Execution phase prompt | `Prompts/Tools/v2/plan_execution.md` | ✅ Done |
| Mode advertisement | `Prompts/System/mode-coder.md` | ✅ Done |
| Prompt wiring | `SystemPromptAssembler.swift` | ✅ Done |
| Tool registration | `ConversationToolProvider.swift` | ✅ Done |
| Artifact detector deferral | `ToolLoopHandler.swift` | ✅ Done |

### Design Principles Applied

| Before (old design) | After (current) |
|--------|-------|
| `task_report` + `task_signoff` (two tools) | `plan` tool with `init/finishTask/raiseQuestion/breakOutCantContinue` |
| Pipeline enforcement | Model-chosen via tool contract |
| Two phases (execute tasks) | Three phases (research → plan → execution) |
| Mid-task `report` was vague | `finishTask` always ends a phase — never initiates |
| No way to ask questions | `raiseQuestion` pauses for user input |
| Artifact detector overrode plan | Artifact detector defers to plan |
| Context injection in pipeline | Phase guidance injected by tool responses |
