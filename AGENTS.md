# Agentic IDE (MAUI/.NET 9)

**Status:** Draft v0.1
**Audience:** Engineering, Product, QA
**Goal:** Ship a VS Code–inspired, native Windows + macOS IDE with a first‑class, fully agentic coding workflow powered by OpenRouter models and hardened tooling. This document specifies scope, architecture, agent contracts, guardrails, and delivery milestones.

---

## 1) Product Goals & Non‑Goals

### Goals

* **Agentic first.** The AI can plan, edit, run, test, and refactor code through explicit, auditable tools.
* **Native MAUI UI.** Fast, stable, keyboard‑centric editor with familiar VS Code ergonomics.
* **Deterministic safety.** All agent actions are previewable, reversible, and logged.
* **Cross‑platform runners.** Uniform abstractions for shell, build, run, and debug on Windows & macOS.
* **Extensibility.** Stable plugin API for tools, languages, and UI panels.
* **Low friction.** Minimal setup; projects work out of the box with common stacks.

### Non‑Goals (v1)

* Full VS Code parity.
* Remote dev containers/SSH.
* Multi‑user collaborative editing.
* Full language server coverage beyond the initial set.

---

## 2) UX Overview

Layout mirrors VS Code conventions while staying native MAUI:

* **Left rail:** Explorer, Search, Source Control, Extensions.
* **Center:** Tabbed editors. **Bottom:** Integrated Terminal (PowerShell on Windows, zsh on macOS).
* **Right panel:** **Agent** pane (chat, plans, diffs, runs, logs).
* **Status bars:** Bottom + left status with mode, model, branch, diagnostics, background tasks.

### Modes

* **Ask:** Q\&A/pair‑assist; read‑only tools (no write/exec).
* **Agent (Autonomous):** Plan→Approve→Execute loop with writes/exec allowed under policy.
* **Suggest:** Agent proposes diffs and commands; user applies.

---

## 3) System Architecture

```text
MAUI UI  ───────────────────────────────────────────────────────────────────────────
  Panels (Explorer, Search, SCM, Extensions, Agent)   Editors   Terminal  Status

Core Services  ───────────────────────────────────────────────────────────────────
  EventBus/Telemetry  |  State Store  |  Indexer (code+symbols+embeddings)  |  VCS
  Tooling Host (sandboxed)  |  Runner Abstraction (shell/build/run/debug)  |  LSP Hub

Agent Orchestrator  ───────────────────────────────────────────────────────────────
  Planner (task graph)  |  Router (tool & subagent)  |  Memory (short/long)  
  Critics & Safety (gates)  |  Cost/Token Budgeter  |  OpenRouter Client

Provider Layer  ──────────────────────────────────────────────────────────────────
  OpenRouter Models (+fallback)  |  Local caches  |  Secrets & Keychain
```

* **State store:** Single source of truth for UI & agent state; snapshotable.
* **Event bus:** Structured events (JSON) for actions, tool calls, diffs, approvals, telemetry.
* **Tooling host:** Runs tools in a sandboxed process with capability scoping and rate limits.
* **Runner abstraction:** Uniform interface over PowerShell/zsh, xcodebuild/dotnet/MSBuild, debuggers.
* **Indexer:** File watcher + incremental code index (lexical + symbol + embedding) for fast search/RAG.
* **LSP hub:** Multiplex to language servers; expose diagnostics & completions to agent and editor.

## 3a) Repository Structure & Platforms

```text
ide.sln
src/
  Ide.Core/
    Ide.Core.csproj
ide/
  ide.csproj
  Platforms/
    MacCatalyst/
    Windows/
xunit/
  xunit.csproj
```

* **Platform targets:** Desktop only. `net9.0-maccatalyst` always; `net9.0-windows10.0.19041.0` conditionally on Windows. Mobile (Android/iOS/Tizen) removed from targets and source tree.
* **Modularity:** Shared logic lives in `src/*` libraries (e.g., `Ide.Core`). The MAUI app references these libraries; test projects reference libraries directly.
* **Solutions:** Root `ide.sln` contains the MAUI app, core libraries, and tests. The nested `ide/ide.sln` is deprecated and slated for removal.

## 4) Agentic Architecture

### Roles

* **MainAgent (Orchestrator):** Owns the user goal, writes a plan, delegates, merges results, asks for approval, and commits.
* **CodeSearchAgent:** Uses Index API to find files/symbols, builds context packs.
* **WriterAgent:** Produces diffs/patches; respects style, tests, and constraints.
* **DebuggerAgent:** Runs tasks, reads logs, proposes fixes; loops with WriterAgent when needed.
* **Critic:** Static check on plans & patches; enforces policies (tests, lint, size, filescope). No write access.

### Control Loop (Agent mode)

1. **Plan** (JSON) → shown in UI; may require approval.
2. **Execute** in bounded steps (budgeted tokens/time/tools).
3. **Critique** plan & outputs; auto‑replan if violated.
4. **Propose Diffs** → preview → user approves → commit on feature branch.
5. **Verify** (build/tests/lint) → report.
6. **Summarize** and store memory.

### Budgets & Safety

* **MaxSteps, MaxTokens, MaxWriteBytes, MaxProcesses** per task.
* **Capabilities:** explicit allow‑list of tools, paths, and commands.
* **Destructive ops** require human approval.

---

## 5) Tool Contract (Stable JSON)

**Principles:** Explicit, idempotent where possible, streaming output, deterministic error codes, bounded results.

```json
{
  "name": "search_codebase",
  "description": "Indexed search with filters.",
  "input_schema": {
    "type": "object",
    "properties": {
      "query": {"type": "string"},
      "kind": {"type": "string", "enum": ["regex","literal","symbol","semantic"]},
      "path_globs": {"type": "array", "items": {"type":"string"}},
      "limit": {"type":"integer","minimum":1,"maximum":500}
    },
    "required": ["query"]
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "matches": {
        "type": "array",
        "items": {
          "type":"object",
          "properties": {
            "file": {"type":"string"},
            "line": {"type":"integer"},
            "preview": {"type":"string"}
          },
          "required": ["file","line","preview"]
        }
      }
    },
    "required": ["matches"]
  }
}
```

**Core Tools (v1):**

* `search_codebase`, `browse_tree` (list dirs/files), `read_files`, `write_files` (atomic, tmp+rename), `patch_files` (unified diff), `create_files`, `delete_files` (gated), `run_shell` (non‑interactive, timeout, cwd), `run_build`, `run_tests`, `git_status`, `git_branch`, `git_commit`, `git_checkout`, `git_revert`, `lsp_query` (symbols/diagnostics), `index_query` (semantic), `format_code`, `lint_code`.

**Shell/Process Policy:**

* Default timeout (e.g., 120s), max log bytes per step, environment whitelist, working dir guards, no network by default (opt‑in per task).

---

## 6) Security, Safety & Permissions

* **Capability tokens:** Each task receives a minimal capability set (tools + paths + commands).
* **Path sandbox:** Whitelisted project root(s); temp dirs; explicit allow for system SDK paths read‑only.
* **Binary hygiene:** Tools cannot write to binaries outside build dirs.
* **Secrets:** Keychain (macOS) / Credential Manager (Windows); never echo in logs; redaction filter.
* **Network:** Off by default; per‑domain allow list when enabled.
* **Approval gates:** Deletes, mass writes (>N files), format‑all, branch force‑push, version bumps.

---

## 7) Memory & Context Strategy

* **Working memory (per task):** Rolling summary of plan, open files, last K tool results.
* **Project memory:** Durable notes (decisions, style, layout, build quirks) in `.agent/memory.json`.
* **Global memory:** Cross‑project preferences (editor conventions, commit style).
* **TTL & size caps:** Auto‑summarize beyond thresholds; manual export/import.
* **Context packing:** Rank by relevance (symbol hits, recent edits, call graph proximity); include diffs not whole files.

---

## 8) Indexing & Retrieval

* **Watch service:** Incremental updates on save/rename/git ops.
* **Indexes:**

  * Lexical (ripgrep‑like)
  * Symbol (Roslyn for .NET; LSP for others)
  * Embedding store (local; privacy‑preserving)
* **Queries:** Hybrid (keyword + symbol + embedding).
* **Warmup:** Background indexing with budget; pause on user activity.

---

## 9) Build/Run/Debug Abstraction

* **Run profiles:** JSON in `.agent/runprofiles.json` (build cmd, run cmd, env, args, cwd).
* **Windows:** PowerShell, `dotnet`, MSBuild, optional WSL for POSIX tasks.
* **macOS:** zsh, `dotnet`, `xcodebuild` where relevant.
* **Output:** Streamed to terminal + captured for agent; structured markers for test results.

---

## 10) Version Control & Rollback

* **Branch per task:** `feat/agent/<slug>` by default.
* **Atomic writes:** Temp files + rename; verify clean `git status` before commit.
* **Patch preview:** Unified diff UI with inline comments.
* **Revert:** Per‑file or per‑commit revert from UI and tool.
* **Commit policy:** Conventional commits; signed commits optional.
* **Automerge:** Disabled by default; require tests green + approval gate.

---

## 11) OpenRouter Integration

* **Model policy:** Reasoning‑heavy vs code‑gen models; fallback chain; health check and auto‑failover.
* **Cost control:** Per‑task token & cost ceilings; mode‑based defaults.
* **Inference:** JSON‑mode/tool‑calling when available; streaming partials for UI.
* **Prompt templates:** System + Project + Task; deterministic seed where supported.
* **Telemetry:** Log model/latency/tokens per step.

---

## 12) Observability & Audit

* **Event stream:** Every plan/tool call/diff/approval/commit with timestamps and hashes.
* **Session replay:** Reconstruct agent runs from events.
* **Privacy:** User‑controlled telemetry on/off; redact secrets.
* **Crash reporting:** Minidumps + last 200 events.

---

## 13) Extension/Plugin System

* **Manifest:** `extension.json` with name, version, scopes, tools, UI contributions.
* **Sandbox:** Tool processes with capability scopes; strict input/output schemas.
* **UI surfaces:** New panels, tree views, commands, status items.
* **Lifecycle:** Install→Enable→Update→Disable; signed packages optional.
* **SDK:** C# interfaces + MAUI UI hooks + testing harness.

---

## 14) Configuration Files

* `.agent/config.json` — mode defaults, model policy, budgets, approvals.
* `.agent/runprofiles.json` — build/run/debug profiles.
* `.agent/memory.json` — project memory (summarized).

**Example:**

```json
{
  "modeDefault": "Suggest",
  "budgets": {"maxSteps": 12, "maxTokens": 120000, "maxWriteBytes": 800000},
  "approvals": {"delete": true, "massWriteThreshold": 20},
  "models": {
    "reasoning": "openrouter/anthropic/claude-opus",
    "codegen": "openrouter/openai/gpt-4.1-mini"
  }
}
```

---

## 15) Error Handling & Safe Writes

* Write tools must be **all‑or‑nothing**; partial failures roll back.
* Large edits split into batches with checkpoints.
* Binary or non‑text files require explicit allow + hash verification.
* User can cancel any step; agent summarizes partial progress.

---

## 16) Performance Targets

* Editor keystroke latency < **20ms** at 99th percentile.
* Search over 100k files < **300ms** warm; < **1.2s** cold.
* Plan generation < **4s** typical with cached context.
* Index incremental update < **150ms** after save.

---

## 17) Testing & Evals

* **Unit tests:** Tools, parsers, indexer, config.
* **Integration:** End‑to‑end runs over sample repos.
* **Agent evals:** Golden tasks (fix bug, add unit test, refactor) with pass/fail.
* **Record‑replay:** Deterministic seeds; network off; fixture repos.
* **Perf tests:** Editor latency, search throughput, indexer CPU.
* **Security tests:** Path traversal, command injection, mass write protection.

---

## 18) Delivery Milestones

* **M0 (2w):** Skeleton MAUI app, panels, tabs, terminal, status bars; EventBus; State store.
* **M1 (3w):** Core tools (read/write/patch/search/run\_shell); Indexer v1; Git status/commit; OpenRouter client.
* **M2 (3w):** Agent orchestrator + Ask/Suggest modes; plan/approval/diff UI; budgets/gates.
* **M3 (3w):** Build/run/test abstraction; DebuggerAgent; eval harness; crash reporting.
* **M4 (3w):** Extensions SDK v0; memory strategy; config files; telemetry toggle.
* **Hardening (2w):** Security pass, perf tune, docs.

---

## 19) Risks & Mitigations

* **Scope creep →** Strict v1 feature list; change control; budget caps in config.
* **Model instability →** Fallback chain, retries with jitter, offline suggest mode.
* **Destructive edits →** Mandatory preview + approval; thresholds; signed commits.
* **Index drift →** Watcher + periodic full reconcile; versioned index.
* **Platform quirks →** Abstraction for shells/build tools; per‑OS test matrices.
* **Perf regressions →** Perf gates in CI; telemetry alerts.

---

## 20) Coding Standards (Enforced)

* SOLID, DRY, KISS, YAGNI.
* Methods ≤ 20 lines; classes ≤ 200 lines (exceptions justified).
* No deep nesting; early returns; pure functions favored.
* Public APIs documented; XML docs required.
* Unit tests mandatory for new code; >80% line coverage in core services.
* Consistent naming & formatting; analyzers + stylecop.
* Dependency Injection for all services; interfaces for test seams.
* No blocking calls on UI thread; async/await throughout.
* Logs structured (JSON) with correlation IDs.

---

## 21) Prompt Contracts (Agent Templates)

### System Template (excerpt)

* You are the **MainAgent** orchestrating developer tasks in a local IDE.
* You must:

  1. Draft a **PLAN** (JSON) with steps, tools, and budgets.
  2. Respect **capabilities** and **path sandbox**.
  3. Propose **diffs** before writes; explain intent succinctly.
  4. Run **tests** and report structured results.
  5. Summarize outcomes and update memory.
* Never execute destructive actions without an approval token.

### PLAN JSON (required)

```json
{
  "goal": "Add unit tests for FooService and fix failing edge case",
  "context": ["FooService.cs:45-120", "FooServiceTests.cs"],
  "steps": [
    {"id":"s1","tool":"search_codebase","args":{"query":"class FooService"}},
    {"id":"s2","tool":"read_files","args":{"files":["src/FooService.cs"]}},
    {"id":"s3","tool":"patch_files","args":{"diff":"..."},"approvalRequired":true},
    {"id":"s4","tool":"run_tests","args":{"profile":"default"}}
  ],
  "budgets": {"maxSteps": 10, "maxWriteBytes": 50000}
}
```

### Critic Policy (excerpt)

* Reject plans touching >20 files or non‑scoped paths.
* Reject diffs lacking tests when functions change behavior.
* Enforce commit message style; block if tests fail.

---

## 22) Glossary

* **Capability:** Granular permission for a tool/path/command.
* **Budget:** Quantitative limit on agent activity (tokens/steps/bytes).
* **Plan:** Declarative step list the agent must follow.
* **Patch:** Unified diff applied atomically.
* **Profile:** Named build/run/test configuration.
