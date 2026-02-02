# Agentic Architecture Spec (osx-ide)

## 1) Mission
Build the best agentic, fully independent IDE experience with:
- deterministic behavior
- user-controlled mode and reasoning
- strong quality gates
- minimal technical debt
- excellent observability

## 2) Core invariants (must never be violated)
### 2.1 User-owned Mode (Chat / Agent)
- **Invariant**: `AIMode` is controlled **only** by the user/UI.
- **Prohibited**:
  - any internal stage flipping `.agent` ↔ `.chat`
  - any prompt content suggesting switching modes
  - any “fallback” that uses a different mode than the user selected
- **Allowed**:
  - internal stages may change **tool permissions** (subset of tools) while keeping the same `AIMode`.

### 2.2 User-owned Reasoning (on/off)
- **Invariant**: `reasoningEnabled` is controlled **only** by the user.
- **Prohibited**:
  - internal toggling of reasoning
  - prompts that allow the model to decide whether to include reasoning
- **Required**:
  - if `reasoningEnabled == true` and user mode is Agent, reasoning is **enforced** on every stage (see §4)

### 2.3 QA is advisory only
- **Invariant**: QA must **not** rewrite the user-visible final answer.
- QA emits a **QA report artifact** (structured) that can be:
  - displayed to the user (optional)
  - fed back as internal guidance for the next iteration (optional)
- QA never has write/edit/delete capability.

### 2.4 Tool permissions are stage-owned, not mode-owned
- `AIMode` is user intent.
- Tool access is an internal policy decision per stage, always consistent and logged.

### 2.5 Delivery/finished state is authoritative and cannot be erased
- Completion must be tracked in run state and logs.
- It must not be removable by QA or “final response retries”.

## 3) Architecture overview

### 3.1 Components
- **ConversationManager**
  - owns UI state (`currentMode`, `currentInput`, `isSending`)
  - starts a run with a `runId`

- **ConversationSendCoordinator**
  - owns the orchestration flow
  - must not mutate `AIMode` or `reasoningEnabled`

- **AIInteractionCoordinator**
  - retrying transport wrapper
  - builds augmented context via `ContextBuilder`
  - sends requests via `AIService`

- **AIService (OpenRouterAIService)**
  - maps messages to OpenRouter schema
  - appends deterministic system prompt content based on policy (see §5)

- **ToolExecutionCoordinator**
  - executes tool calls
  - streams progress messages into history

- **Policy owner** (new)
  - single authoritative decision-maker for:
    - tool subset per stage
    - prompt set per stage
    - reasoning requirements per stage
  - must be pure / deterministic and unit tested

- **PromptRepository** (new)
  - loads all prompts from markdown files
  - supports variable interpolation

- **QA reviewer** (refactored)
  - produces advisory QA report
  - uses restricted read-only tool set

- **Context compression** (existing or refactored)
  - summarizes older history deterministically
  - maintains “rolling memory” without context pollution

- **Index + Local memory** (existing CodebaseIndex)
  - supports semantic retrieval
  - stores structured local memories (project context)

### 3.2 Data flow (high level)
1. User sends message in UI
2. Run starts with `runId`, `AIMode`, `reasoningEnabled`
3. Coordinator performs:
   - Macro reasoning warmup (Stage: `warmup`)
   - Tool loop execution (Stage: `act` / `tool_followup`)
   - Delivery gate (Stage: `delivery_check`)
   - QA advisory review (Stage: `qa_review`) (non-mutating)
4. Final message appended
5. Run snapshot persisted

## 4) Reasoning enforcement model (macro + micro)

### 4.1 Macro warmup reasoning (once per user message)
Goal: high-quality “pre-run warmup” that plans the work.

- Stage: `warmup`
- Required when:
  - `mode == Agent` and `reasoningEnabled == true`
- Output:
  - `<ide_reasoning>` block with required sections
  - plus a short user-visible statement of next steps

**Macro requirements**:
- Analyze: interpret user request
- Research: identify what must be inspected (files/entrypoints/logs)
- Plan: explicit milestones
- Reflect: risks and assumptions
- Action: immediate next tool actions
- Delivery: must start with `NEEDS_WORK` until complete

### 4.2 Micro reasoning between steps (every subsequent agentic request)
Goal: “small reflection” to help the model converge without rehashing full plan.

- Stage: `micro_step`
- Required when:
  - `mode == Agent` and `reasoningEnabled == true`

**Micro requirements**:
- Reflect briefly on:
  - what just happened (tool outputs, errors)
  - what we will do next
  - why that next step is correct
- Keep concise: 3–8 bullets total.

### 4.3 Reasoning retention policy (avoid context pollution)
- The UI may display reasoning for transparency.
- The next model request should not be polluted by old reasoning.

**Rule**:
- Persist only a compact **ReasoningOutcome** in the conversation chain.
- Discard the full `<ide_reasoning>` text from subsequent model history.

**ReasoningOutcome content**:
- `plan_delta`: what changed in plan
- `next_action`: what tool call(s) will be made next
- `known_risks`: one-line
- `delivery_state`: `DONE` / `NEEDS_WORK`

### 4.4 QA reasoning
- If `reasoningEnabled == true`, QA must also include reasoning,
  but using the **micro format** (short) and must not rewrite the answer.

## 5) Prompts (externalized to Markdown)

### 5.1 Prompt inventory
All prompts live under `osx-ide/Prompts/` (exact structure can be adjusted):

- `Prompts/base/system.md`
- `Prompts/base/project_root_context.md`
- `Prompts/agent/mode_addition.md`
- `Prompts/agent/reasoning_macro.md`
- `Prompts/agent/reasoning_micro.md`
- `Prompts/agent/tool_loop_context.md`
- `Prompts/agent/empty_response_recovery.md`
- `Prompts/agent/user_input_request_block.md`
- `Prompts/agent/delivery_gate.md`

Current incremental migration (already in repo):

- `Prompts/ConversationFlow/Corrections/force_tool_followup.md`
- `Prompts/ConversationFlow/Corrections/no_user_input_next_step.md`
- `Prompts/ConversationFlow/Corrections/empty_response_followup.md`
- `Prompts/ConversationFlow/DeliveryGate/reasoning_format_correction.md`
- `Prompts/ConversationFlow/DeliveryGate/low_quality_reasoning.md`
- `Prompts/ConversationFlow/DeliveryGate/reasoning_only_no_answer.md`
- `Prompts/ConversationFlow/DeliveryGate/enforce_delivery_completion.md`
- `Prompts/ConversationFlow/QA/tool_output_review_system.md`
- `Prompts/ConversationFlow/QA/quality_review_system.md`

- `Prompts/qa/system.md`
- `Prompts/qa/review_micro_reasoning.md`
- `Prompts/qa/report_schema.md`

### 5.2 Prompt composition rules
- System prompt is composed deterministically:
  - base prompt
  - project root context
  - mode addition (derived from user mode, but never instructs switching)
  - stage prompt (warmup/tool/micro/delivery/qa)
  - reasoning prompt (only if user enabled)

### 5.3 Prompt interpolation
Allowed variables:
- `{{project_root}}`
- `{{user_input}}`
- `{{tool_summary}}`
- `{{last_step_outcome}}`

## 6) Tool policy (capability matrix)

### 6.1 Principle
- Tool access depends on stage.
- Never change `AIMode`.

### 6.2 Suggested tool sets
- **Agent execution (act/tool_followup)**
  - full tool set for edits + reads

- **Delivery-only step**
  - tools disabled (empty list)

- **QA review (read-only)**
  - index read/search/list only
  - no patch/write/delete

## 7) Context compression (history summarization)

### 7.1 Purpose
Prevent context window overflow while preserving continuity.

### 7.2 Requirements
- Summarize old turns into a structured summary message:
  - goals
  - decisions
  - current plan
  - open issues
  - important tool outputs
- Do not include old `<ide_reasoning>` blocks.

### 7.3 Trigger policy
- Trigger based on:
  - message count threshold
  - token estimate threshold
- Always deterministic, logged.

## 8) Index + local memory integration

### 8.1 Retrieval
- Use CodebaseIndex to:
  - locate entry points
  - retrieve relevant symbols
  - retrieve local memories

### 8.2 Memory writing policy
- Memories are written only when:
  - a run completes successfully
  - a stable decision is made (architecture choice)
- Memory entries should be concise and queryable.

### 8.3 Memory tiers
- project-level facts (paths, build commands)
- architecture-level decisions
- recent run outcomes

## 9) Observability and logging (must be airtight)

### 9.1 Required log fields for every OpenRouter request
- `conversationId`
- `runId`
- `userMode` (the UI-selected mode)
- `stage`
- `toolCount`
- `reasoningEnabled`

### 9.2 Assertions
- **Mode invariance**: log and assert the request mode equals the user-selected mode.
- **Reasoning invariance**: if enabled, stage prompt includes reasoning instruction.
- **Tool invariance**: stage tool set matches policy.

## 10) Failure modes and recovery

### 10.1 Empty model response
- Stage-owned recovery prompt.
- Must not switch mode.

### 10.2 Model asks user for diffs/files
- Stage-owned correction prompt.
- Must proceed autonomously.

### 10.3 Tool failures
- structured recovery guidance
- retry with changed parameters

## 11) Project tracker (refactor checklist)

### 11.1 Invariants
- [ ] Remove any internal code that can switch `.agent` ↔ `.chat`
- [ ] Remove any prompt text suggesting mode switching
- [ ] Make `reasoningEnabled` strictly user-owned and deterministic

### 11.2 Prompts
- [x] Create `Prompts/` directory
- [ ] Move all inline prompts from Swift into `.md`
- [x] Add `PromptRepository` + interpolation

### 11.3 Policy
- [x] Implement centralized `ConversationPolicy`
- [ ] Unit test: stage -> tools/prompt/reasoning

### 11.4 QA
- [x] Replace QA rewriting with advisory `QAReport`
- [x] Restrict QA tools to read-only
- [x] Ensure QA never mutates final message

### 11.5 Reasoning
- [ ] Macro warmup reasoning on each user message (Agent + reasoning enabled)
- [ ] Micro reasoning on each subsequent agentic step
- [ ] Strip full reasoning from history; persist `ReasoningOutcome`

### 11.6 Context compression
- [x] Define summarization trigger
- [x] Persist structured summary
- [x] Exclude `<ide_reasoning>` from summaries

### 11.7 Local memory
- [x] Define memory write policy
- [ ] Add tests for memory retrieval usage

### 11.8 Observability
- [x] Add `runId` + `stage` to OpenRouter logging
- [x] Assert invariants in debug builds

