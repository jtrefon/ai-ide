# Plan Tool Specification

**Tool name:** `plan`

**File:** `osx-ide/Services/Planning/PlanTool.swift`

**Type:** `AITool` (Swift protocol)

**Registered in:** `ConversationToolProvider.swift`

---

## Purpose

A structured task planner that lets the model break complex work into focused, one-at-a-time tasks. The model opts in by calling `plan.init`, then progresses through three phases by calling `plan.finishTask`.

---

## Actions

### `init` — Opt into planning

**Parameters:** None (context comes from the conversation)

**Phase:** Enters research phase.

**Response:** Returns `plan_research.md` prompt — instructs the model to research using all tools, then call `finishTask` with a task breakdown.

```json
{
  "status": "success",
  "message": "Planning mode. Research the problem using all available tools...",
  "content": {
    "action": "init",
    "phase": "researching"
  }
}
```

### `finishTask` — End current phase

**Parameters:**
- `summary` (string, required): During research: proposed task breakdown (one task per line). During execution: what was done, files changed, verification.

**Phase transitions:**
- Research → execution: parses summary into `PlanItem` list, activates first task
- Execution → next: marks current task complete, advances to next pending
- Execution → done: marks last task complete, returns `all_done: true`

**Response during execution (not last):**
```json
{
  "status": "success",
  "message": "Well done. Task 1/3 complete. Now working on task 2.",
  "content": {
    "action": "finishTask",
    "phase": "executing",
    "task": "Design repository protocol",
    "purpose": "Repository interface decouples data access from business logic",
    "done_criteria": "Protocol compiles with CRUD method signatures",
    "progress": "1/3"
  }
}
```

**Response for last task:**
```json
{
  "status": "success",
  "message": "All 3 tasks complete. Provide a final summary.",
  "content": {
    "action": "finishTask",
    "all_done": true,
    "progress": "3/3"
  }
}
```

### `raiseQuestion` — Ask user for clarification

**Parameters:**
- `question` (string, required): The question for the user.

**Response:**
```json
{
  "status": "question",
  "message": "Should I use async/await or Combine for the repository?",
  "content": {
    "action": "raiseQuestion"
  }
}
```

The framework pauses execution and waits for user input.

### `breakOutCantContinue` — Abort the plan

**Parameters:**
- `summary` (string, required): Why the plan cannot continue.
- `blocker_reason` (string, required): What is needed to unblock.

**Response:**
```json
{
  "status": "blocked",
  "message": "Plan aborted. Missing CoreData model entity.",
  "content": {
    "action": "breakOutCantContinue",
    "reason": "TodoEntity.xcdatamodeld doesn't exist"
  }
}
```

All remaining tasks are marked blocked.

---

## Phase Detection

The tool determines the current phase from the plan's state in `ConversationPlanStore`:

| Plan state | Phase |
|-----------|-------|
| No plan | Before `init` |
| Plan exists, items empty | Research |
| Plan exists, items have active task | Execution |
| Plan exists, no active or pending items | Done |

---

## Error Codes

| Code | Meaning | Recoverable |
|------|---------|------------|
| `INVALID_ACTION` | Action must be init/finishTask/raiseQuestion/breakOutCantContinue | Yes |
| `MISSING_SUMMARY` | Summary required for finishTask and breakOutCantContinue | Yes |
| `MISSING_QUESTION` | Question required for raiseQuestion | Yes |
| `MISSING_BLOCKER_REASON` | blocker_reason required for breakOutCantContinue | Yes |
| `NO_ACTIVE_TASK` | No active task found to complete | No |

---

## Prompt Files

| File | When loaded | Contains |
|------|------------|----------|
| `Prompts/Tools/v2/plan.md` | System prompt (always) | Purpose, When to Use, Methods table, Parameters |
| `Prompts/Tools/v2/plan_research.md` | On `init` call | Research guidance, tool list, finishTask instruction |
| `Prompts/Tools/v2/plan_execution.md` | On `finishTask` transition | Execution guidance, template vars filled |

---

## Data Structures

See `Services/Planning/TaskPlan.swift`:

- `TaskPlan` — the persisted plan with id, goal, items, currentIndex
- `PlanItem` — individual task with description, purpose, context, doneCriteria, status
- `ItemStatus` — pending, active, completed, blocked

Stored via `ConversationPlanStore` (actor, JSON file persistence, LRU cache).

---

## Dependencies

- `ConversationPlanStore.shared` — for persisting/loading plans
- `PromptRepository.shared` — for loading phase guidance markdown
- `AIToolExecutor` — injects `_conversation_id` into tool arguments
- `ToolLoopHandler` — artifact detector defers to plan's `isComplete`

---

## Lifecycle

```
Model calls plan.init
  → tool creates empty plan in store
  → tool returns research prompt
  → model researches (reads files, searches, browses)
  → model calls plan.finishTask with task breakdown
  → tool parses breakdown, stores plan items, returns execution prompt
  → model works on task 1
  → model calls plan.finishTask with summary
  → tool marks task 1 complete, activates task 2
  → model receives task 2 context
  → ...repeat until all done...
  → tool returns all_done: true
  → model provides final summary
```
