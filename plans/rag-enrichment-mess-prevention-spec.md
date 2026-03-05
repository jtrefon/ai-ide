---
title: RAG + Enrichment + Codebase Mess Prevention Spec
status: draft
owner: AI Platform
last_updated: 2026-03-04
---

## 1) Problem Statement

Current indexing, enrichment, and RAG capabilities are strong individually, but not yet fully orchestrated toward one outcome:

1. Give the agent exact, high-signal code context for each task.
2. Prevent duplicate implementations and dead code growth.
3. Continuously improve quality/debt posture while coding.

This spec defines a delivery plan for a unified **Context Intelligence + Mess Prevention** system.

---

## 2) Goals and Non-Goals

## Goals

1. Keep RAG enabled by default for all agent requests.
2. Improve retrieval precision with intent-aware ranking and segment-level context.
3. Introduce proactive **duplicate/dead-code prevention gates** before code write operations.
4. Add ongoing debt/quality observability (including status bar signal).
5. Add feedback loops so retrieval and prevention improve over time.
6. Improve agent speed, consistency, and first-pass correctness through better context, policy, and execution loops.

## Non-Goals

1. Fully automated large-scale refactors in v1.
2. Perfect elimination of all duplication in v1.
3. Replacing all existing linting/tooling.

## Initiative Scope Decision

This remains **one unified initiative**, not separate projects.

Mess prevention is a core workstream, but it should ship together with the broader agent-empowerment work:

1. **Retrieval Intelligence** (better evidence selection and context quality)
2. **Execution Reliability** (fewer retries, better tool-loop decisions, safer edits)
3. **Mess Prevention** (duplicate/dead-code prevention and cleanup)
4. **Agent Performance** (latency, token efficiency, and throughput)
5. **Agent Consistency** (predictable behavior, policy compliance, stable outputs)

This bundling avoids local optimization (e.g., preventing duplicates but still retrieving weak context).

---

## 3) Principles

1. **Prevention over cleanup**: stop duplicate/dead code at generation time.
2. **Evidence-first coding**: require references to existing implementations before write.
3. **Durability-aware memory**: stable architecture facts vs transient issue signals.
4. **Low-friction UX**: strong safeguards without slowing normal flow.
5. **Composable architecture**: clear modules, protocol boundaries, testability.

---

## 4) Current State Summary

## Existing strengths

1. Index and symbol query substrate is present.
2. AI enrichment persists summaries and quality scores.
3. RAG is already invoked in request flow.
4. Embedding-based memory retrieval exists with fallback behavior.
5. Status model already exposes indexing/enrichment/retrieval and quality metrics.

## Current gaps

1. Retrieval is mostly token/symbol based, not truly intent-aware.
2. Enrichment metadata is not deeply fused into retrieval ranking.
3. No hard prevention gate for duplicate implementation before writes.
4. No first-class dead code detection workflow tied to agent decisions.
5. Context packaging is mostly plain text; evidence is not typed/scored.

---

## 5) Target Architecture

## 5.1 Context Intelligence Pipeline

1. **Task Intent Classifier**
   - Classifies request: bugfix, feature, refactor, explanation, tests, cleanup.
2. **Candidate Retrieval**
   - Sources: summaries, symbols, segment embeddings, memories, tests, quality hotspots.
3. **Fusion Ranker**
   - Combines semantic relevance + architecture proximity + quality/debt signals + freshness.
4. **Evidence Packager**
   - Produces compact typed evidence cards with confidence and source spans.
5. **Prompt Assembler**
   - Injects only top evidence under budget constraints by stage.

## 5.3 Reliability and Performance Pipeline

1. **Stage-Aware Context Budgeting**
   - Allocate context differently for planning, execution, and QA/review stages.
2. **Tool-Loop Reliability Controls**
   - Prefer focused context and enforce retry corrections when tool calls fail.
3. **Token Efficiency Controls**
   - Preserve high-value evidence and truncate low-value context first.
4. **Deterministic Policy Checks**
   - Gate unsafe/low-confidence operations with clear pass/warn/block outcomes.
5. **Outcome Feedback Learning**
   - Track which evidence and policies improved first-pass success and tune weights.

## 5.2 Mess Prevention Pipeline

1. **Pre-Write Duplicate Guard**
   - Runs before code generation write/apply.
   - Detects semantic and structural overlap with existing implementations.
2. **Linkage Verifier**
   - Ensures generated code is wired into existing flow (not side-by-side orphan).
3. **Dead Code Risk Guard**
   - Flags additions that are unused/unreferenced or shadow existing paths.
4. **Policy Engine**
   - Blocks, warns, or requires explicit override based on confidence thresholds.
5. **Post-Write Auditor**
   - Confirms no new duplicate/dead-code debt introduced by accepted patch.

---

## 6) RAG Strategy Decision

## Decision

- Keep **RAG always enabled** by default.
- Do **adaptive depth**, not adaptive on/off.

## Rationale

1. Matches user preference and current performance characteristics.
2. Maintains agent awareness for all turns.
3. Still protects context quality by tuning retrieval breadth, ranking, and packing.

## Policy

1. Always run retrieval.
2. Vary source weights/top-K by intent and stage.
3. Under high context pressure, drop low-confidence evidence first.

---

## 7) Data Model Extensions

## 7.1 Enrichment Entities

Add structured enrichment payload:

- `responsibility_summary` (stable)
- `public_contracts` (stable)
- `integration_points` (stable)
- `quality_signals` (semi-stable)
- `issue_signals` (transient)
- `confidence`
- `observed_at`
- `source_revision`
- `expires_at` (for transient entries)

## 7.2 Evidence Card (retrieval output)

- `evidence_id`
- `type` (summary/symbol/segment/memory/issue/test)
- `file_path`
- `line_start`, `line_end`
- `score_total`
- `score_components`
- `confidence`
- `freshness`
- `why_selected`

## 7.3 Prevention Finding

- `finding_type` (duplicate_impl, dead_code_risk, parallel_path_risk, orphan_api)
- `severity`
- `candidate_file_span`
- `existing_file_spans`
- `explanation`
- `block_recommended`

---

## 8) Ranking and Guard Heuristics

## 8.1 Retrieval ranking (v1)

`total_score = semantic_similarity * intent_weight + architecture_proximity + quality_hotspot_boost + recency_boost - staleness_penalty`

## 8.2 Duplicate prevention (v1)

1. Symbol collision check (name/signature/module boundary).
2. Behavior similarity check (embedding + AST-lite fingerprint).
3. Neighbor check for existing pattern extension points.
4. If high overlap and no extension rationale => block + suggest reuse target.

## 8.3 Dead code risk (v1)

1. New symbol has no inbound references in planned integration path.
2. New path duplicates existing dispatch/registration entry.
3. New implementation not wired to command registry / DI graph / UI flow.
4. Mark as warning/block according to confidence.

---

## 9) Agent Flow Changes

## 9.1 Before generation

1. Retrieve evidence cards.
2. Run duplicate/dead-code pre-check against intended edits.
3. Add mandatory “reuse candidates” section to model context.

## 9.2 During generation

1. Require model to cite chosen existing implementation anchor(s).
2. If model proposes new module while equivalent exists, force justification.

## 9.3 Before apply_patch

1. Validate no block-level prevention finding unresolved.
2. If unresolved, request revise pass (reuse-first rewrite).

## 9.4 After apply_patch

1. Recompute prevention checks on changed files.
2. Emit telemetry outcome and debt delta.

---

## 10) UX and Observability

## 10.1 Status Bar / Gauge

Add a compact composite gauge:

- `Readiness` (index freshness + enrichment coverage + retrieval confidence)
- `Debt Pressure` (dup risk + dead code risk + quality trend)
- `Guard` status (clear/warn/block)

## 10.2 New events

- `RetrievalEvidencePreparedEvent`
- `PreWritePreventionCheckStartedEvent`
- `PreWritePreventionCheckCompletedEvent`
- `DuplicateRiskDetectedEvent`
- `DeadCodeRiskDetectedEvent`
- `DebtPressureUpdatedEvent`

## 10.3 Core KPIs

1. Duplicate implementation incident rate.
2. Dead code introduction rate.
3. Retrieval precision@K for accepted edits.
4. First-pass successful integration rate.
5. Mean time to safe patch.
6. Average end-to-end turn latency.
7. Tool-call success rate per stage.
8. Context token efficiency (useful/total).
9. Policy violation rate (target: downward trend).
10. Retry rate per task category.

---

## 11) Delivery Plan

## Phase 1 — Retrieval quality and evidence framing (1-2 weeks)

1. Implement evidence card model and retrieval output conversion.
2. Add intent classifier + adaptive weights (depth only, always-on retrieval).
3. Fuse quality/debt signals into ranking.
4. Add tests for ranking determinism and context packing.
5. Add stage-aware context budgeting rules.

## Phase 2 — Prevention gates v1 (2-3 weeks)

1. Implement pre-write duplicate guard.
2. Implement dead code risk guard and linkage verifier.
3. Add policy outcomes: pass/warn/block.
4. Add revise loop integration for blocked writes.
5. Add unit + integration tests with synthetic duplicate scenarios.

## Phase 2.5 — Reliability hardening (parallel, 1-2 weeks)

1. Add deterministic stage policy checks before and after tool execution.
2. Improve retry behavior with failure-class-specific correction prompts.
3. Add guardrails for low-confidence generation paths.
4. Add telemetry for retry causes and resolution quality.

## Phase 3 — UI + telemetry + debt operations (1-2 weeks)

1. Reintroduce status gauge in status bar.
2. Add prevention and debt telemetry stream.
3. Add debt delta reporting per accepted patch.
4. Add dashboard markdown snapshots in `QUALITY_TRACKER.md`.
5. Add KPI snapshots for speed/consistency metrics.

## Phase 4 — Cleanup assistant mode (optional, 2+ weeks)

1. Scheduled cleanup proposals (duplicate consolidation / dead code removal).
2. Human-in-the-loop review workflow.
3. Safe auto-fix classes for low-risk cases.

---

## 12) Testing Strategy

1. **Unit tests**
   - ranker scoring
   - prevention heuristics
   - staleness/TTL behavior
2. **Integration tests**
   - end-to-end retrieval -> generation -> pre-write gate
3. **Regression suites**
   - known duplicate side-by-side incidents
   - known dead-code pileup patterns
4. **Performance tests**
   - retrieval latency budgets
   - pre-write guard overhead budgets

---

## 13) Risks and Mitigations

1. **False positives block valid innovation**
   - Mitigation: confidence thresholds + explicit override path + explainability.
2. **Over-constrained generation**
   - Mitigation: warn mode first, block only on high-confidence findings.
3. **Telemetry noise**
   - Mitigation: strict event taxonomy and sampling for verbose streams.
4. **Stale issue memory**
   - Mitigation: TTL, revision binding, and freshness penalties.

---

## 14) Initial Backlog (trackable items)

1. [ ] Define `EvidenceCard` domain model and mappers.
2. [ ] Implement retrieval fusion ranker (intent-weighted).
3. [ ] Add segment-level retrieval support in index.
4. [ ] Add `PreWriteDuplicateGuard` service and tests.
5. [ ] Add `PreWriteDeadCodeRiskGuard` service and tests.
6. [ ] Integrate prevention checks into generation/apply flow.
7. [ ] Add status bar readiness/debt gauge.
8. [ ] Add telemetry events + KPI collection.
9. [ ] Update `QUALITY_TRACKER.md` with new metrics sections.
10. [ ] Define override policy and audit trail.

---

## 15) Open Decisions

1. Which confidence thresholds map to warn vs block in v1?
2. Which file types are included for segment embedding v1?
3. Should prevention checks run on every tool loop iteration or only pre-apply?
4. How should override justifications be persisted and surfaced?

---

## 16) Definition of Done (v1)

1. Retrieval always-on with adaptive depth and evidence cards.
2. Duplicate/dead-code prevention checks active pre-write.
3. Agent references existing implementations before creating new ones.
4. Status bar shows readiness/debt/guard indicators.
5. KPI baseline captured and visible in markdown tracking.
6. Test coverage added for ranking and prevention core flows.
7. Reliability + performance KPIs captured with weekly trend reporting.
8. Measurable reduction in duplicate/dead-code incidents versus baseline.
