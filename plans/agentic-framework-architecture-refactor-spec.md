---
title: Agentic Framework Architecture Refactor Specification
status: draft
owner: AI Platform
last_updated: 2026-03-06
---

## 1) Executive Summary

This specification defines the replacement architecture for the current agentic execution framework.

The current framework is over-orchestrated, overly prompt-driven, and too dependent on model self-correction. It mixes planning, execution, recovery, delivery validation, and QA in one broad graph. That design has produced the following classes of failures:

1. Unnecessary planning for simple requests.
2. Excessive reasoning and oversized assistant output.
3. Tool-loop instability and redundant follow-up model calls.
4. Mixed-mode responses that combine planning, execution intent, status summaries, and malformed tool calls.
5. Insufficiently isolated execution phases, which increases the risk of request contamination and poor recovery behavior.
6. High operational complexity, making failures harder to reason about and harder to test thoroughly.

This specification replaces the current model-first orchestration with a controller-first execution architecture built around the following principles:

1. Classify before acting.
2. Plan only when complexity justifies planning.
3. Keep execution loops narrow, deterministic, and bounded.
4. Make the controller own retries, stop conditions, and failure classification.
5. Keep reasoning and user-visible text compact.
6. Eliminate dead orchestration paths, obsolete tests, and compatibility shims as part of the refactor.
7. Ship with full production-parity test coverage and zero known architecture debt.

---

## 2) Problem Statement

The current agentic framework is not meeting reliability, clarity, or performance goals.

### Observed problems

1. Planning is mandatory in the production path instead of being optional and need-driven.
2. User-visible plan messages are injected into chat history, polluting both UX and model context.
3. The framework uses multiple prompt-based correction and enforcement stages to repair model behavior after the fact.
4. The model is asked to do too many jobs at once in a single turn:
   - decide whether to act
   - plan
   - reason
   - call tools
   - summarize progress
   - satisfy delivery-state constraints
5. Recovery logic often triggers additional model calls instead of deterministic controller action.
6. The framework has too many orchestration phases for a single user turn.
7. Telemetry is not sufficiently rich to diagnose all failures quickly.
8. Harness coverage exists for current regressions, but not yet for the target future behavior.

### Consequences

1. Latency is higher than necessary.
2. Token usage is higher than necessary.
3. Failure modes are harder to isolate.
4. Small requests are slower and noisier than they should be.
5. Looping and malformed tool retries are more likely.
6. The codebase accumulates orchestration debt and test debt.

---

## 3) Goals

### Primary goals

1. Build a precise, bounded, controller-first agentic framework.
2. Make planning an optional capability instead of a mandatory stage.
3. Remove prompt-chaos and collapse redundant orchestration phases.
4. Ensure the agent handles simple requests simply and complex requests robustly.
5. Ensure the execution loop is deterministic, observable, and resilient.
6. Prevent looping, malformed tool execution, and mixed-mode response behavior.
7. Replace existing fragile recovery behavior with explicit controller policies.
8. Deliver a full refactor with cleanup of obsolete code and tests.
9. Maintain a strict zero-debt policy during the migration.
10. Maximize performance, clarity, and testability.

### Secondary goals

1. Reduce user-visible orchestration noise.
2. Improve telemetry quality and diagnosis speed.
3. Preserve production-path parity in harness coverage.
4. Improve maintainability with smaller, single-purpose components.

---

## 4) Non-Goals

1. Incrementally patching the existing graph forever.
2. Preserving old orchestration concepts solely for compatibility if they are no longer justified.
3. Maintaining duplicate paths for both old and new execution models long term.
4. Adding more corrective prompt stages to compensate for structural flaws.
5. Keeping user-visible planning or reasoning output as a default requirement.

---

## 5) Design Principles

1. **Controller-first architecture**
   - The controller decides the state machine.
   - The model provides bounded outputs within that state machine.

2. **Optional planning**
   - Planning is a tool/capability, not a mandatory orchestration step.

3. **Single responsibility components**
   - Classification, planning, execution, validation, finalization, and telemetry each have distinct responsibilities.

4. **Deterministic recovery**
   - Recovery is driven primarily by controller logic, not open-ended prompt retries.

5. **Strict output contracts**
   - Each stage allows only a small, well-defined set of valid outputs.

6. **Fail closed for unsafe or malformed execution**
   - Invalid tool arguments, ambiguous outputs, and repeated no-progress states must stop safely.

7. **Bounded iteration**
   - Every loop must have explicit budgets, stop conditions, and progress rules.

8. **Minimal user-visible ceremony**
   - Plans and meta-reasoning should remain internal unless explicitly needed or requested.

9. **Zero-debt migration**
   - Old architecture code and tests must be removed once replaced.
   - No parallel permanent systems.

10. **Production parity**
   - Harness coverage must validate the same production path the app runs.

---

## 6) Current-State Diagnosis

### 6.1 Architectural failures

1. Mandatory planning nodes are always executed in agent mode.
2. Planning state is written into user-visible chat history.
3. Multiple correction and delivery-enforcement phases exist after the main execution phase.
4. The framework can re-enter tool execution from several downstream phases.
5. Final delivery generation is over-specified.
6. QA review is embedded in the mainline path rather than being a clearly justified optional pass.

### 6.2 Behavioral failures

1. Simple status requests trigger planning and execution framing.
2. Assistant messages can become too verbose and contain content that should have been structured tool arguments.
3. Tool retries can be driven by model self-correction loops instead of controller policy.
4. Delivery-state and reasoning formatting constraints can distort normal behavior.

### 6.3 Observability failures

1. Tool call snapshots store keys but not enough payload metadata.
2. Retry reasons are not captured as first-class telemetry decisions.
3. Intent classification is not explicit, so it cannot be audited.
4. Planning invocation reasons are not explicitly recorded.

---

## 7) Target Architecture Overview

The target system replaces the current broad orchestration graph with a small, explicit execution pipeline.

### Core pipeline

1. **Intent Classifier**
2. **Planning Capability** (optional)
3. **Execution Controller**
4. **Tool Validation and Execution Layer**
5. **Progress and Stop Evaluator**
6. **Finalizer**
7. **Telemetry and Audit Layer**

### High-level flow

```text
User Request
  -> Intent Classification
  -> Optional Planning
  -> Execution Controller Loop
       -> Model Step
       -> Output Validation
       -> Tool Execution
       -> Progress Evaluation
  -> Finalization
  -> Telemetry Emission
```

### Permitted top-level modes

1. `answer`
2. `direct_execute`
3. `planned_execute`
4. `research_then_execute`
5. `blocked`

---

## 8) Target Components

## 8.1 Intent Classifier

### Responsibility

Classify the request into one execution mode before any planning or tool execution occurs.

### Output contract

The classifier returns a structured result containing:

- `intent_class`
- `requires_tools`
- `requires_plan`
- `requires_research`
- `complexity_level`
- `confidence`
- `reason_codes`

### Rules

1. Simple informational requests should classify to `answer`.
2. Small bounded edits should classify to `direct_execute`.
3. Long-running, multi-file, or staged tasks should classify to `planned_execute`.
4. Requests with insufficient project understanding but clear execution intent should classify to `research_then_execute`.
5. Requests blocked on missing permissions or missing critical context should classify to `blocked`.

### Non-negotiable invariant

No planning or execution begins before intent classification completes.

---

## 8.2 Planning Capability

### Responsibility

Provide a plan only when the controller determines a plan is needed.

### Planning policy

Planning is allowed only when one or more of the following is true:

1. The request spans multiple milestones.
2. The request affects multiple domains or subsystems.
3. The request is expected to require more than a small number of tool iterations.
4. The request contains explicit sequencing requirements.
5. The user explicitly asks for a plan.
6. The controller determines that task ambiguity requires a tracked execution structure.

### Planning output

The planning capability returns:

- `plan_id`
- `plan_summary`
- `plan_steps`
- `success_criteria`
- `verification_targets`
- `rollback_considerations`

### UX policy

1. Plans are internal by default.
2. Plans may be summarized compactly in UI if desired.
3. Full plan markdown is shown only when:
   - the user asks for it, or
   - the controller decides it is necessary for long-running tracked execution.

### Non-negotiable invariant

There is no unconditional plan generation in agent mode.

---

## 8.3 Execution Controller

### Responsibility

Own the runtime state machine for model interaction and tool use.

### Execution state

The controller maintains a structured execution state with fields including:

- `turn_id`
- `intent_class`
- `mode`
- `plan_id`
- `tool_iteration`
- `max_tool_iterations`
- `progress_status`
- `last_tool_batch_signature`
- `last_mutation_target_signature`
- `repeated_failure_count`
- `no_progress_count`
- `files_touched`
- `tests_requested`
- `tests_run`
- `stop_reason`
- `finalization_reason`

### Allowed execution-step outputs

For any model step, exactly one of the following is allowed:

1. `tool_batch`
2. `final_answer`
3. `blocked_or_clarification`

Mixed-mode outputs are invalid.

### Controller duties

1. Decide whether another model step is allowed.
2. Validate output mode.
3. Reject malformed or ambiguous model outputs.
4. Execute tool batches.
5. Track progress.
6. Stop immediately on controller-defined failure thresholds.
7. Request a final answer only when the loop has legitimately completed or deterministically failed.

### Non-negotiable invariant

The controller, not the model, is the owner of loop control and termination policy.

---

## 8.4 Tool Validation and Execution Layer

### Responsibility

Validate tool calls before execution and execute only valid, allowed actions.

### Validation layers

1. **Schema validation**
   - Required fields present.
   - Types correct.

2. **Semantic validation**
   - Mutation tools must include complete executable payloads.
   - Targets must be valid for the project root.

3. **Policy validation**
   - Tools allowed for current mode and stage.
   - Safety and permission checks satisfied.

4. **Budget validation**
   - Payload size within thresholds.
   - Mutation volume within step limits.

### Mutation policy

1. Prefer targeted edits over full rewrites when appropriate.
2. Full-file writes should be limited to:
   - file creation
   - explicit full replacement cases
3. Oversized text emitted outside tool arguments is invalid execution output.

### Non-negotiable invariant

Malformed mutation payloads fail closed and do not trigger uncontrolled retry loops.

---

## 8.5 Progress and Stop Evaluator

### Responsibility

Determine whether the execution loop is progressing, stalled, complete, or failed.

### Progress signals

1. Successful tool completion.
2. State advancement toward explicit success criteria.
3. Verified file changes.
4. Successful tests or validation checks.
5. Evidence of movement to new targets rather than repeated identical actions.

### Stop reasons

The controller must stop with an explicit reason code when any threshold is hit.

Required stop reasons include:

- `completed`
- `blocked_missing_context`
- `blocked_permission`
- `malformed_tool_call`
- `ambiguous_model_output`
- `repeated_failed_signature`
- `repeated_completed_signature`
- `repeated_write_target`
- `read_only_loop_stall`
- `no_progress`
- `iteration_budget_exceeded`
- `payload_budget_exceeded`
- `controller_policy_violation`

### Non-negotiable invariant

Every completed run must end with exactly one explicit stop reason.

---

## 8.6 Finalizer

### Responsibility

Produce the final user-visible result based on controller state and verified execution facts.

### Finalization policy

1. Final answers must be concise by default.
2. Final answers must not claim work that did not happen.
3. Final answers should be largely controller-grounded, not free-form speculative summaries.
4. Delivery semantics such as done vs unfinished should be driven by controller state, not inferred from model preference.

### Finalization output model

The finalizer should produce:

- `outcome`
- `objective`
- `work_performed`
- `files_touched`
- `verification`
- `remaining_risks`
- `rollback_hint`
- `stop_reason`

### UX policy

1. No mandatory reasoning block.
2. No mandatory plan echo.
3. No giant summary scaffold for simple requests.
4. Summary depth should scale with task complexity.

---

## 8.7 Telemetry and Audit Layer

### Responsibility

Provide complete observability for diagnosis, regression tracking, and performance optimization.

### Required telemetry dimensions

1. Turn metadata
2. Intent classification decision
3. Planning invocation decision
4. Model-step output mode
5. Tool call metadata
6. Tool execution outcomes
7. Retry reasons
8. Stop reason
9. Token and latency budgets
10. Progress vs no-progress indicators

### Required tool telemetry fields

Each tool call record must include:

- `tool_call_id`
- `tool_name`
- `argument_keys`
- `argument_byte_count`
- `argument_preview_hash`
- `argument_preview_truncated`
- `validation_result`
- `execution_result`
- `target_file`
- `controller_decision`

### Non-negotiable invariant

Telemetry must be rich enough to diagnose truncation, malformed arguments, repetition, mixed-mode outputs, and retry causes without guesswork.

---

## 9) Invariants and Safety Rules

The target architecture must enforce the following invariants.

### Request handling invariants

1. Every request is intent-classified before planning or execution.
2. Only one top-level mode is active for a turn.
3. User-visible plan emission is not the default.

### Execution invariants

4. Every model step returns exactly one allowed output mode.
5. The controller rejects mixed-mode outputs.
6. All tool calls are schema-validated before execution.
7. Mutation tools fail closed on malformed payloads.
8. Loop iterations are bounded.
9. Controller retries are bounded and reason-coded.
10. Every run ends with one explicit stop reason.

### State invariants

11. Internal execution state is authoritative over free-form assistant text.
12. The final answer must be consistent with controller state and verified results.
13. No downstream stage may re-open execution implicitly after finalization begins.

### Debt invariants

14. Deprecated architecture code must not remain after migration completes.
15. Deprecated tests that enforce obsolete behavior must be removed or rewritten.
16. No permanent compatibility shims are allowed unless explicitly approved and time-bounded.

---

## 10) Removal Targets From the Current Architecture

The following current concepts are considered obsolete or structurally suspect and must be removed, collapsed, or heavily redesigned.

### Mandatory removal or redesign targets

1. Mandatory strategic planning in the default agent path.
2. Mandatory tactical planning in the default agent path.
3. User-visible plan insertion into chat history as a default behavior.
4. Prompt-based reasoning-correction stages as a mainline recovery mechanism.
5. Prompt-based delivery-gate retries as a mainline recovery mechanism.
6. Multiple downstream conditional tool-loop re-entry points.
7. Over-specified final-delivery prompt scaffolding for ordinary tasks.
8. Mainline QA stages that are always paid for regardless of task need.

### Cleanup rule

For every replaced module, do all of the following in the same initiative:

1. Remove dead code.
2. Remove dead tests.
3. Remove dead telemetry fields.
4. Remove dead prompt templates.
5. Remove dead snapshot expectations.
6. Remove compatibility glue no longer needed.

No deferred cleanup backlog is permitted.

---

## 11) Proposed Module Structure

### New core modules

1. `AgentIntentClassifier`
2. `AgentPlanningPolicy`
3. `AgentPlanner`
4. `AgentExecutionController`
5. `AgentStepOutputValidator`
6. `AgentProgressEvaluator`
7. `AgentStopPolicy`
8. `AgentFinalizer`
9. `AgentTelemetryRecorder`

### Supporting modules

1. `ExecutionStateStore`
2. `ToolPayloadInspector`
3. `ToolBatchSignatureCalculator`
4. `ExecutionBudgetPolicy`
5. `TaskComplexityEvaluator`

### Structural boundaries

1. Classifier must not execute tools.
2. Planner must not own execution loop logic.
3. Finalizer must not determine truth from model claims alone.
4. Telemetry recorder must observe decisions rather than infer them later.

---

## 12) Prompt Strategy

The target architecture should reduce prompt scope and separate responsibilities.

### Prompt families

1. **Classifier prompt**
   - Structured classification only.
2. **Planner prompt**
   - Used only when planning is explicitly justified.
3. **Execution prompt**
   - Used during the active execution loop.
4. **Finalization prompt**
   - Used only when synthesis is genuinely needed.

### Prompt constraints

1. No prompt should combine planning, execution, and finalization responsibilities.
2. No prompt should require verbose reasoning by default.
3. Execution prompts should optimize for valid tool calls, not narrative prose.
4. Prompt size must be budget-aware by stage.

---

## 13) Performance Strategy

### Performance objectives

1. Minimize unnecessary model calls.
2. Minimize unnecessary tokens.
3. Reduce orchestration overhead on simple tasks.
4. Bound tool-loop iterations tightly.
5. Keep telemetry useful without excessive runtime cost.

### Required performance measures

1. One classifier step per user turn.
2. Zero planning step for simple requests.
3. No more than one recovery retry for narrowly defined recoverable output issues unless explicitly justified.
4. Controller-owned hard budgets for:
   - model turns
   - tool iterations
   - payload size
   - final response length

### Optimization principles

1. Fast path for `answer` intent.
2. Fast path for small direct execution tasks.
3. Optional planning only when needed.
4. No multi-stage orchestration ceremony for simple requests.

---

## 14) Testing Strategy

The new architecture must ship with exhaustive testing and production-path parity.

## 14.1 Testing goals

1. Validate every controller decision type.
2. Validate every stop reason.
3. Validate plan gating behavior.
4. Validate tool-loop safety and boundedness.
5. Validate finalization correctness.
6. Validate telemetry completeness.
7. Validate removal of obsolete behaviors.

## 14.2 Test pyramid

### Unit tests

Required coverage areas:

1. Intent classification policy.
2. Planning gating policy.
3. Complexity thresholds.
4. Output mode validation.
5. Stop policy.
6. Progress evaluation.
7. payload inspection.
8. finalization mapping.
9. telemetry record generation.

### Integration tests

Required coverage areas:

1. `answer` flow without planning.
2. `direct_execute` flow without planning.
3. `planned_execute` flow with internal plan.
4. `research_then_execute` flow with read-first behavior.
5. malformed tool call fail-closed behavior.
6. repeated signature stop behavior.
7. repeated write target stop behavior.
8. no-progress stop behavior.
9. bounded retry behavior.
10. final answer consistency.

### Production-parity harness tests

Required coverage areas:

1. Real production path simple informational request must not emit a plan.
2. Real production path small edit must not emit heavy reasoning or visible plan by default.
3. Real production path complex task must invoke planning only when thresholds are met.
4. Real production path malformed mutation must fail closed exactly once or under an explicitly bounded retry rule.
5. Real production path must not re-enter execution after finalization starts.
6. Real production path telemetry must include intent class, plan decision, retry reason, and stop reason.
7. Real production path must not emit mixed-mode output.

### Regression tests

Must explicitly cover current observed failures:

1. planner overreach for simple informational requests
2. repeated malformed write retries
3. heavy reasoning on simple asks
4. tool-loop stall through repeated read-only batches
5. giant assistant content replacing structured execution
6. empty or truncated tool arguments
7. finalization drift between controller truth and assistant wording

## 14.3 Deletion and rewrite policy for tests

1. Tests that encode obsolete architecture behavior must be deleted.
2. Tests that currently reproduce broken behavior for diagnosis must be preserved only until replacement target tests exist.
3. Once the new architecture is active, old-behavior reproduction tests must be either:
   - rewritten to assert the new expected behavior, or
   - removed if no longer relevant.
4. No obsolete harness expectations may remain after the migration completes.

---

## 15) Telemetry Specification

### Required turn-level fields

- `turn_id`
- `conversation_id`
- `run_id`
- `intent_class`
- `complexity_level`
- `planning_invoked`
- `planning_reason_codes`
- `tool_iteration_count`
- `retry_count`
- `stop_reason`
- `latency_ms`
- `input_token_estimate`
- `output_token_estimate`

### Required step-level fields

- `step_index`
- `step_type`
- `allowed_output_modes`
- `observed_output_mode`
- `validation_status`
- `retry_reason`
- `controller_decision`

### Required outcome fields

- `completed`
- `files_touched`
- `tests_run`
- `verification_status`
- `finalization_reason`

### Snapshot policy

Snapshots must be readable, diff-friendly, and sufficient for failure diagnosis without requiring additional hidden logs.

---

## 16) Migration Strategy

The migration must be staged, but each stage must leave the codebase in a clean, shippable state.

## 16.1 Refactor phases

### Phase 0: Baseline and guardrails

1. Freeze the current failure corpus in harness and sandbox references.
2. Add missing telemetry needed to prove future improvements.
3. Document all current failure reason codes and graph responsibilities.

### Phase 1: Introduce intent classification

1. Add `AgentIntentClassifier`.
2. Route turns into explicit intent classes.
3. Add tests verifying simple requests no longer require planning.
4. Keep existing execution path behind a transitional adapter only if strictly necessary.

### Phase 2: Gate planning behind policy

1. Add `AgentPlanningPolicy`.
2. Disable unconditional strategic/tactical planning for non-complex tasks.
3. Move plan storage to internal-only default use.
4. Remove visible chat-plan injection from normal paths.
5. Rewrite harness tests to assert no-plan behavior for simple asks.

### Phase 3: Introduce execution controller

1. Add `AgentExecutionController`.
2. Centralize loop control, retry policy, and stop reasons.
3. Move repeated-signature, write-target, and no-progress checks under one controller.
4. Reduce or remove graph-based downstream tool re-entry stages.

### Phase 4: Replace prompt-based correction stages

1. Remove reasoning-correction dependency from mainline control.
2. Remove delivery-gate dependency from mainline control.
3. Replace downstream prompt recovery with deterministic controller policy.
4. Remove obsolete prompt templates and tests.

### Phase 5: Replace finalization path

1. Add `AgentFinalizer`.
2. Drive final delivery from controller truth and verified outputs.
3. Remove over-specified default final summary requirements.
4. Rewrite finalization tests for concise, truthful output.

### Phase 6: Remove old graph and dead code

1. Delete obsolete graph nodes and wiring.
2. Delete obsolete prompts and stores no longer required.
3. Delete obsolete tests.
4. Delete obsolete telemetry fields and snapshot expectations.
5. Confirm no dead paths remain.

### Phase 7: Hardening and performance pass

1. Measure latency and token improvements.
2. Validate stress scenarios.
3. Validate sandbox parity.
4. Finalize architecture docs.

---

## 17) Transitional Compatibility Rules

Temporary compatibility is allowed only when all of the following are true:

1. The transition is necessary to keep the app working during a staged refactor.
2. The compatibility code has a clearly defined removal point.
3. Tests explicitly cover the temporary behavior.
4. The compatibility path does not become the new permanent architecture.

### Required rule

Every temporary bridge must have a removal task in the same initiative.

---

## 18) Code Debt Policy

This initiative follows a strict zero-debt policy.

### Zero-debt rules

1. No new architecture may land with known dead branches.
2. No TODO-based debt handoff is allowed for core architecture gaps.
3. No duplicate orchestration frameworks may coexist permanently.
4. No obsolete prompts or tests may remain after replacement is complete.
5. No telemetry ambiguity may remain for the primary failure classes.
6. Every introduced abstraction must justify its existence with a single clear responsibility.

### Acceptance standard

The initiative is not complete until:

1. the new architecture is default,
2. the old architecture is removed,
3. obsolete tests are cleaned up,
4. target tests pass,
5. telemetry is complete,
6. sandbox validation confirms the new behavior.

---

## 19) Acceptance Criteria

The architecture refactor is complete only when all of the following are true.

### Functional acceptance

1. Simple informational agent requests do not generate plans by default.
2. Small edit requests do not trigger heavy reasoning or delivery ceremony.
3. Complex tasks invoke planning only when justified.
4. Tool loops are bounded and stop deterministically.
5. Malformed tool calls fail closed without uncontrolled retries.
6. Final responses are concise and truthful.
7. No downstream phase can implicitly restart execution after finalization begins.

### Quality acceptance

8. Production-path harness validates target behavior.
9. Obsolete graph nodes and prompt stages are removed.
10. Old behavior tests are rewritten or removed.
11. Telemetry captures intent, plan decision, retry reason, and stop reason.
12. No known architecture debt remains.

### Performance acceptance

13. Simple requests are materially faster and cheaper than before.
14. The number of model calls per simple turn is reduced.
15. Token budgets are stage-appropriate and bounded.

---

## 20) Delivery Checklist

### Architecture

- [ ] Intent classifier implemented
- [ ] Planning policy implemented
- [ ] Planner made optional
- [ ] Execution controller implemented
- [ ] Stop policy implemented
- [ ] Finalizer implemented
- [ ] Telemetry recorder upgraded

### Cleanup

- [ ] Mandatory planning nodes removed or neutralized
- [ ] Visible default plan injection removed
- [ ] Reasoning-correction mainline dependency removed
- [ ] Delivery-gate mainline dependency removed
- [ ] Obsolete final summary scaffolding removed or reduced
- [ ] Obsolete QA mainline stages removed or gated
- [ ] Dead prompts deleted
- [ ] Dead tests deleted or rewritten
- [ ] Dead telemetry fields deleted

### Testing

- [ ] Unit tests complete
- [ ] Integration tests complete
- [ ] Production-parity harness tests complete
- [ ] Regression tests updated for target behavior
- [ ] Sandbox validation complete

### Release readiness

- [ ] Performance validated
- [ ] Failure corpus re-run successfully
- [ ] No known architecture debt remains

---

## 21) Recommended Implementation Order

To reduce risk and maximize leverage, implement in this order:

1. Intent classification
2. Planning gate
3. Internal-only plan handling
4. Execution controller
5. Stop policy consolidation
6. Finalizer replacement
7. Telemetry expansion
8. Old graph removal
9. Old test and prompt cleanup

This order addresses the highest-value structural issues first while keeping the migration controlled.

---

## 22) Final Decision

The current framework should be refactored toward a controller-first agentic system with optional planning, deterministic execution control, explicit stop reasons, internal state authority, compact UX, and full production-parity test coverage.

This is the approved target direction for the refactor initiative defined in this document.
