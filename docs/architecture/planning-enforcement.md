# Planning Tool & Loop Enforcement

## Problem

The AI agent often starts work without a clear plan, skips steps, or completes only part of a task before declaring done. The system needs:

1. A **dedicated planning tool** that stores structured plans with trackable items
2. A **loop enforcer** that prevents the agent from exiting until all plan items are complete or explicitly blocked

## Current State

The application has these planning primitives but they are not connected into a cohesive enforcement system:

- **PlanChecklistTracker** — Parses `[ ]` / `[x]` checkboxes from plan text, tracks completion
- **ConversationPlanStore** — Persists plans per conversation with LRU eviction
- **StrategicPlanningNode** / **TacticalPlanningNode** — Generate plans for Agent mode
- **DispatcherNode** — Can route back to tool loop when plan is incomplete

What's missing: a **dedicated tool** for the model to explicitly create and update plans, and a **hard enforcement gate** that prevents loop exit while items remain open.

---

## Proposed: `plan_update` Tool

### Purpose
A dedicated tool for the AI to create, update, and track structured plans. This replaces the current ad-hoc markdown checklist approach with a formal, machine-readable structure that the framework can enforce.

### Tool Definition

**Name:** `plan_update`

**Purpose:** Create or update a structured task plan with checklist items. The plan is stored by the framework and tracked for completion. The tool loop enforcer will NOT allow exit while incomplete items remain.

**Parameters:**
- `action` (required, string): `create` | `update` | `complete` | `block`
  - `create`: Initialize a new plan with items
  - `update`: Mark one or more items complete, add new items
  - `complete`: Mark the entire plan as complete
  - `block`: Mark an item as blocked (cannot proceed, reason required)
- `items` (required, array of objects): The plan items
  - Each item: `{ "id": "1", "description": "Create repository interface", "status": "pending" | "completed" | "blocked" }`
- `blocker_reason` (optional, string): Required when `action=block`. Explains why an item cannot proceed.

### Output Structure (ToolFeedback envelope)
```
status: success
content:
  items:
    - id: "1"
      description: "Create repository interface"
      status: "completed"
    - id: "2"
      description: "Implement repository"
      status: "pending"
  progress: "50%"  # computed by the framework
```

### Usage Flow

**Step 1 — Create Plan:**
```
tool: plan_update
args:
  action: "create"
  items:
    - id: "1"
      description: "Read current persistence layer files"
      status: "pending"
    - id: "2"
      description: "Design repository interface"
      status: "pending"
    - id: "3"
      description: "Implement TodoRepository"
      status: "pending"
    - id: "4"
      description: "Update consumers"
      status: "pending"
    - id: "5"
      description: "Run tests to verify"
      status: "pending"
```

**Step 2 — Mark Item Complete:**
```
tool: plan_update
args:
  action: "update"
  items:
    - id: "1"
      description: "Read current persistence layer files"
      status: "completed"
```

**Step 3 — All Done:**
```
tool: plan_update
args:
  action: "complete"
  items: []  # implies all remaining are completed
```

### Framework Integration

The `plan_update` tool connects to:
1. **ConversationPlanStore** — Persists the plan for the conversation
2. **PlanChecklistTracker** — Computes progress percentages
3. **Loop Enforcer** (see below) — Gate that checks plan completion

---

## Loop Enforcer

### Purpose
A hard gate in the ToolLoopHandler that prevents the agent from exiting the tool loop while incomplete plan items exist. This ensures the agent cannot skip tasks or deliver partial work.

### Location
The enforcer runs in the ToolLoopHandler between each tool iteration, before the model is asked for a final response.

### Logic

```
for each iteration:
  execute tools
  check plan status via PlanChecklistTracker:
    if plan.isComplete → allow exit to final_response
    if plan.hasBlockedItems → allow exit, but require explanation
    if plan.hasIncompleteItems:
      if model's response has no tool calls:
        → route BACK to tool loop (not final_response)
        → inject context: "Plan still has {N} incomplete items"
      if model's response has tool calls:
        → continue normal tool loop
    if no plan exists → behave as current (no enforcement)
```

### Integration Points

1. **DispatcherNode** — Currently checks `planProgress.isComplete` before routing to final response. This needs to be hardened: if the plan is incomplete, the dispatcher MUST route to the tool loop regardless of other signals.

2. **ToolLoopHandler** — The `deliveryStatus` recovery logic (lines ~2595-2614) currently allows the model to end the loop by returning `deliveryStatus: done`. With the enforcer, `deliveryStatus: done` is ignored if the plan has incomplete items.

3. **FinalResponseNode** — Should check plan status before delivering: if plan incomplete, append a summary of what remains.

### Hard Enforcement Logic

```swift
func canExitToolLoop(plan: Plan?, modelResponse: AIServiceResponse) -> Bool {
    guard let plan else { return true }  // No plan = no enforcement
    if plan.isComplete { return true }
    if plan.hasBlockedItems { return true }  // Explicit blockers are OK
    return false  // Incomplete items → stay in loop
}
```

---

## Tool Prompt

The `plan_update` tool needs a prompt following the template format:

# plan_update Tool

## Purpose
Create or update a structured task plan with trackable checklist items. The framework enforces plan completion — you cannot exit the tool loop while items remain incomplete.

## When to Use
- At the START of any multi-step task to create a plan
- AFTER completing a step to mark it done
- When a step is BLOCKED and cannot proceed
- Before declaring a task complete (use action=complete)

## When NOT to Use
- Do NOT use for single-step tasks (just do the work)
- Do NOT use for asking questions (use Chat mode)
- Do NOT use at the end of Agent mode (Agent has its own planning)

## Parameters
- **action** (required, string): "create" | "update" | "complete" | "block"
- **items** (required, array): Array of plan items with id, description, status
- **blocker_reason** (optional, string): Required when action="block"

## Usage Examples
- Create plan: `{ "action": "create", "items": [{"id": "1", "description": "Read files", "status": "pending"}, ...] }`
- Complete step: `{ "action": "update", "items": [{"id": "1", "description": "Read files", "status": "completed"}] }`
- All done: `{ "action": "complete", "items": [] }`
- Block item: `{ "action": "block", "items": [{"id": "2", "status": "blocked"}], "blocker_reason": "File not found" }`

## Output Structure
Returns a ToolFeedback envelope with the current plan progress:
- **content.items**: Array of plan items with their status
- **progress**: "75%" computed by the framework

## Success Indicators
- status: "success" — plan was updated
- progress shows the current completion percentage
- If not 100%, the loop enforcer will keep the tool loop running

## Error Handling
- INVALID_ACTION: action must be create/update/complete/block
- MISSING_ITEMS: items parameter is required for create and update
- MISSING_BLOCKER_REASON: blocker_reason is required when action=block

## Best Practices
1. Create the plan FIRST before doing any work
2. Keep items granular enough to track but not so granular it's tedious
3. Use meaningful descriptions so the framework can report progress
4. Mark items completed as soon as they're done
5. If stuck, use action=block with a clear reason rather than abandoning

## Integration Notes
- The plan is stored in ConversationPlanStore per conversation
- PlanChecklistTracker computes progress automatically
- The Loop Enforcer prevents exit while incomplete items remain
- Blocked items ALLOW exit — the model explains the blocker in the final response
