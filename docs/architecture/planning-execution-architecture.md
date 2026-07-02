# Planning & Execution Architecture v2

## Philosophy

The current approach — inject the entire plan, let the model self-manage — fails because:

1. **Context dilution**: The plan takes up tokens, and as the conversation grows, the plan gets compressed/garbled
2. **Loss of focus**: The model sees ALL tasks at once and jumps ahead, repeats, or forgets where it is
3. **No anchor**: After context compression, the model can't reliably recover what was done vs what remains
4. **No enforcement**: The model can declare "done" at any point — the framework can't verify

**The fix**: Instead of dumping the entire plan into context, the framework manages the plan and feeds **one task at a time**. The model focuses on ONE thing, delivers it, signs off, and the framework injects the next.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FRAMEWORK (MANAGER)                         │
│                                                                     │
│  ┌──────────────┐    ┌──────────────────┐    ┌──────────────────┐  │
│  │ Plan Store    │    │ Task Injector    │    │ Sign-off Gate    │  │
│  │ (persisted)   │───▶│ (one-at-a-time)  │───▶│ (enforces        │  │
│  │              │    │                  │    │  completion)     │  │
│  └──────────────┘    └──────────────────┘    └──────────────────┘  │
│                              │                       │              │
│                              ▼                       ▼              │
│                    ┌──────────────────┐    ┌──────────────────┐  │
│                    │ Context Window   │    │ Tool Loop        │  │
│                    │ (current task    │    │ (model executes)  │  │
│                    │  only)           │    │                  │  │
│                    └──────────────────┘    └──────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### The Critical Shift

| Before | After |
|--------|-------|
| Entire plan in context | One task in context |
| Model self-manages progress | Framework manages progress |
| Model decides when done | Framework enforces task completion |
| Compression loses everything | Compression loses only current task's working context |
| Large context required | Small context window works (even 8k models) |
| Model direction dilutes over time | Model gets fresh direction per task |

---

## Data Structures

### PlanStore (Persisted, survives compression)

```swift
struct TaskPlan: Codable, Sendable {
    let id: String           // UUID — links plan to conversation
    let goal: String         // Single sentence: WHAT we're achieving
    let mode: AIMode         // coder or agent
    let items: [PlanItem]    // Ordered list of all tasks
    let createdAt: Date
    var completedAt: Date?
    var currentIndex: Int    // Which item the model is working on
}
```

### PlanItem (One unit of work)

```swift
struct PlanItem: Codable, Sendable {
    let id: String
    let description: String          // WHAT to do (actionable)
    let purpose: String              // WHY this exists (context, connects to goal)
    let files: [String]              // WHERE — relevant file paths
    let doneCriteria: String         // HOW to verify completion
    var status: ItemStatus           // pending | active | completed | blocked
    var summary: String?             // Model's sign-off summary when done
    var blockedReason: String?       // If status == blocked
}

enum ItemStatus: String, Codable, Sendable {
    case pending
    case active
    case completed
    case blocked
}
```

### Example Plan Document

```json
{
  "goal": "Refactor persistence layer into repository pattern",
  "mode": "coder",
  "currentIndex": 0,
  "items": [
    {
      "id": "task-1",
      "description": "Analyze current persistence code",
      "purpose": "Must understand existing implementation before designing replacement",
      "files": ["src/data/TodoDataManager.swift", "src/models/Todo.swift"],
      "doneCriteria": "All persistence-related files have been read and understood",
      "status": "active"
    },
    {
      "id": "task-2",
      "description": "Design and implement TodoRepository protocol",
      "purpose": "Repository interface decouples data access from business logic",
      "files": ["src/repository/TodoRepository.swift"],
      "doneCriteria": "Protocol compiles with CRUD method signatures, build passes",
      "status": "pending"
    },
    {
      "id": "task-3",
      "description": "Implement repository with CoreData backend",
      "purpose": "Concrete implementation that replaces TodoDataManager",
      "files": ["src/data/TodoDataManager.swift", "src/repository/TodoRepository.swift"],
      "doneCriteria": "All CRUD operations work, existing tests pass",
      "status": "pending"
    }
  ]
}
```

---

## Tool: `plan_signoff`

The model no longer manages the plan. Instead there's a single tool for task lifecycle:

### Tool Definition

**Name:** `plan_signoff`

**Purpose:** Complete the current task, provide a summary, and signal readiness for the next task. The framework then injects the next task into context.

**Parameters:**
- `summary` (required, string): Brief summary of what was done, what files were changed, and verification result. This becomes the permanent record of the task.
- `blocked` (optional, boolean): Set true if this task cannot be completed
- `blocked_reason` (optional, string): Required if blocked=true. Explain why.

**Output Structure:**
```
status: success
content:
  task_completed: "task-1"
  next_task: { id: "task-2", description: "Design and implement TodoRepository protocol" }
  progress: "1/3 — 33% complete"
  message: |
    ✅ Task complete: Analyze current persistence code
    Summary: Read TodoDataManager.swift and Todo.swift. Current implementation uses
    direct CoreData calls in the view model layer. No abstraction layer exists.

    ▶ Next: Design and implement TodoRepository protocol
    Purpose: Repository interface decouples data access from business logic
    Files: src/repository/TodoRepository.swift
    Done when: Protocol compiles with CRUD method signatures
```

### Tool Prompt

```
# plan_signoff Tool

## Purpose
Complete the current task, provide a summary, and advance to the next task.
The framework manages the task queue. You work on ONE task at a time.

## When to Use
- When you have COMPLETED the current task (met all done criteria)
- When the current task is BLOCKED and cannot proceed

## When NOT to Use
- Do NOT use for partial progress (just keep working)
- Do NOT use to skip tasks (the framework enforces order)

## Parameters
- **summary** (required, string): What was done, what files changed, verification result.
- **blocked** (optional, boolean): Set true if task is blocked.
- **blocked_reason** (optional, string): Why the task cannot proceed.

## Output Structure
Returns the next task description, purpose, files, and done criteria.
Previous task summary is recorded permanently.
The framework handles all task queue management.

## Best Practices
1. Only call when the task is TRULY done — verify with builds/tests first
2. Write a useful summary that could reorient you after context compression
3. If blocked, explain exactly what's needed to unblock
4. Do NOT plan future tasks — the framework handles sequencing
```

---

## Context Injection Flow

### What the Model Sees at Each Step

**Step 1 — Task Begins:**
```
You are working on Task 1 of 3.

📋 Current Task: Analyze current persistence code
   Purpose: Must understand existing implementation before designing replacement
   Files: src/data/TodoDataManager.swift, src/models/Todo.swift
   Done when: All persistence-related files have been read and understood

Use plan_signoff when complete.
(No other tasks are visible — focus on this one.)
```

**Step 2 — After plan_signoff:**
```
✅ Task 1 complete: Analyze current persistence code
   Summary: Read TodoDataManager.swift and Todo.swift...

You are working on Task 2 of 3.

📋 Current Task: Design and implement TodoRepository protocol
   Purpose: Repository interface decouples data access from business logic
   Files: src/repository/TodoRepository.swift
   Done when: Protocol compiles with CRUD method signatures, build passes
```

**Step 3 — All tasks complete:**
```
🎉 All 3 tasks complete!

Goal: Refactor persistence layer into repository pattern
Summary:
  - Task 1: Analyzed existing code ...
  - Task 2: Designed protocol ...
  - Task 3: Implemented repository ...

Final summary for user.
```

### What Survives Context Compression

After compression, only these elements are re-injected:
1. The **goal** (one sentence)
2. The **current task** (with purpose, files, done criteria)
3. The **completed tasks list** (id + summary only — full descriptions are dropped)
4. The **last tool result or error**

This is roughly 1/10th of the full plan. The model can fully reorient from this.

---

## Loop Enforcement

### Sign-off Gate (in ToolLoopHandler)

```swift
// After each tool iteration:
if currentItem.status == .active {
    let planProgress = PlanChecklistTracker.progress(in: plan)
    
    // Check if model's response contains plan_signoff
    if !hasSignoff(modelResponse) {
        // Model is still working — continue tool loop
        continue
    }
    
    // Model called plan_signoff — validate
    if planProgress.isComplete {
        // All items done — allow final response
        return finalResponse()
    }
    
    // Advance to next item
    let nextItem = planStore.advanceToNext()
    injectTask(nextItem)  // Replace context with next task
    continue
}
```

### What Gets Blocked

- Model cannot exit the tool loop while a task is `active` (no `plan_signoff` called)
- Model cannot skip tasks (framework controls `currentIndex`)
- Model cannot see future tasks (prevents context roaming)
- After compression, only current task context is restored

---

## Implementation Plan

### Phase 1: Data Layer (existing, needs refactor)

- Refactor `ConversationPlanStore` to store `TaskPlan` struct instead of raw markdown
- Refactor `PlanChecklistTracker` to work with `PlanItem.status` instead of `[ ]` / `[x]`
- Update `PlanOutlineView` to render structured plan
- Update `PlanActiveItemResolver` to return current `PlanItem`

### Phase 2: Tool (new)

- Create `PlanSignoffTool.swift` — the `plan_signoff` AITool
- Register in `ConversationToolProvider.swift`
- Create `Prompts/Tools/v2/plan_signoff.md` prompt

### Phase 3: Context Injection (new)

- Add `TaskInjector` — injects current task context into system prompt
- Integrate with `SystemPromptAssembler` — replaces the full-plan injection with per-task injection
- Handle context compression — store only completed item summaries

### Phase 4: Loop Enforcement (new)

- Add sign-off gate in `ToolLoopHandler`
- Wire to `DispatcherNode` — prevent routing to final response while tasks remain
- Handle blocked tasks — allow exit but require explanation

### Phase 5: Plan Generation (refactor)

- Update `StrategicPlanningNode` to generate structured `TaskPlan` (not raw markdown)
- Update `TacticalPlanningNode` to refine items with purpose/files/done-criteria

---

## Advantage Over Current Approach

| Aspect | Current (passive plan) | Proposed (managed plan) |
|--------|----------------------|------------------------|
| Context usage | Entire plan + history | Current task only |
| Scalability | Limited by context window | Works with any context window |
| Focus | Model self-manages | Framework enforces one-at-a-time |
| Recovery after compression | Unreliable — vague plan | Complete — task has full context |
| Completion enforcement | None — model decides | Hard — framework enforces |
| Task summary | Lost in history | Saved permanently |
| Small model support | Poor — needs large context | Excellent — minimal context per task |
