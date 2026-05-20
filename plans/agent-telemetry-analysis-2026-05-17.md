# Agent Telemetry Analysis — Production Readiness Assessment

**Date:** 2026-05-17
**Source:** `sandbox/todo-app/.ide/logs/` (ai-trace, app, crash, indexing)
**Run analyzed:** `0242D616-B695-4B71-9EED-A733A04571B7` (Agent mode, local MLX model)
**Request:** "Can you review overall progress and quality of the application to assess production readiness?"

---

## Executive Summary

The agent run failed to deliver a meaningful production readiness assessment. It spent 7+ minutes in a tool loop that made 0/8 plan progress, repeatedly attempting to read hallucinated file paths. The root cause is a combination of: local model hallucination, ineffective recovery mechanisms, missing RAG context injection, and the agent's strategy of guessing file names instead of discovering them.

---

## Detailed Timeline

| Time | Event | Detail |
|---|---|---|
| 10:42:20 | Index initialized | Skipped reindex (persisted data exists), project: todo-app |
| 10:42:49 | User message sent | 94 char input, Agent mode, 19 messages history |
| 10:43:21 | Recovery #1 | planProgress: 0/8 — agent couldn't start |
| 10:43:52 | Tool loop iteration 1 | 4 tool calls: 3 read_file errors (hallucinated paths), 1 success |
| 10:44:09 | Recovery #2 | planProgress: 0/8 |
| 10:44:41 | Tool loop iteration 1 (again) | 1 list_dir — success (14 bytes) |
| 10:45:40 | Recovery #3 | planProgress: 0/8 |
| 10:46:18 | Tool loop iteration 1 (again) | 3 read_file: 1 success, 2 errors (same hallucinated paths) |
| 10:46:41 | Recovery #4 | planProgress: 0/8 |
| 10:47:20 | Tool loop iteration 1 (again) | 1 read_file error (same hallucinated path) |
| 10:48:01 | Tool loop iteration 2 | 1 list_dir error (absolute path rejected) |
| 10:48:26 | Recovery #5 | planProgress: 0/8 |
| 10:49:16 | Recovery #6 | planProgress: 0/8 |
| 10:49:50 | Post-continuation recovery | deliveryStatus: missing, planProgress: 0/8 |

---

## Key Findings

### 1. File Path Hallucination (Critical)

The model repeatedly attempted to read files that don't exist:

| Hallucinated Path | Attempts | Actual File |
|---|---|---|
| `src/components/TaskList.tsx` | 2 | `src/components/TodoApp.tsx` |
| `src/services/TaskService.ts` | 2 | No services/ TypeScript files |
| `src/components/FilterBar.tsx` | 2 | `src/components/TemplateSwitcher.tsx` |

**Root cause:** The model guessed file names from a prior architecture summary in the conversation history (messages 14-16), rather than discovering the actual project structure.

### 2. Flawed Agent Strategy

The agent's plan was:
```
1. Identify target files and understand current structure
   - Use read_file/list_files to inspect relevant sources
2. Design minimal change set
3. Implement changes
4. Verify correctness
```

But the actual execution was:
```
→ Try read_file on 4 guessed paths
→ 3 fail, 1 succeeds
→ Try list_dir (succeeds)
→ Try read_file on 3 guessed paths AGAIN
→ 2 fail, 1 succeeds
→ Try list_dir with absolute path (fails)
→ Keep retrying same paths
```

The agent never learned from failures — it kept trying the same non-existent paths.

### 3. Continuation Recovery is Ineffective (7 triggers, 0 progress)

The recovery mechanism fired 7 times but never changed the approach:
- It should detect repeated failures on the same paths
- It should force a strategy pivot (e.g., "list all files first")
- It should escalate to a simpler approach (read project structure before reading individual files)

### 4. Relative Path Resolution Bug

The model used `/src/components` as an absolute path:
```
list_dir error: "Access denied: '/src/components' is outside the project directory"
```
The PathValidator correctly rejected this, but the model should be prompted to use project-relative paths.

### 5. RAG Context Not Injected

The indexing log shows "Skipping initial project reindex because persisted index data already exists." But the model was not provided with a file listing or project structure in context. The `contextBuilder` appears to not include basic project structure when constructing the AI request.

### 6. Model Configuration Issues (Pre-existing)

Earlier in the conversation history (messages 1-10), the local MLX model had repeated configuration errors:
- `gemma4` → unsupported model type
- `Missing field 'hidden_size'` 
- `Missing field 'attn_logit_softcapping'`
- `Key model.embed_tokens.weight not found`

These are model loading issues, not agent bugs, but they affect reliability.

### 7. Telemetry Shows Degraded Quality

From the telemetry entry:
- `repeatedAssistantUpdates: 1` — duplicate assistant messages
- `deduplicatedToolCalls: 0` — no deduplication happened despite repeated identical calls
- `iteration: 1` repeated 5 times — never advanced to iteration 3+

---

## How Far Are We From the Vision?

**Vision:** An agent that takes a request, builds solid understanding of application context via RAG, and prepares strategy for best execution.

**Current State:**

| Capability | Status | Gap |
|---|---|---|
| Understand project structure | ❌ | Guesses file names instead of discovering |
| Learn from tool errors | ❌ | Repeats same failed calls |
| Recovery from failures | ⚠️ | Triggers but doesn't improve strategy |
| RAG context injection | ❌ | Index exists but context not provided to model |
| Path resolution | ⚠️ | Sandbox works but model uses absolute paths |
| Plan execution | ❌ | 0/8 plan progress after 7 minutes |
| Model reliability | ❌ | 6 consecutive errors before first success |
| Tool deduplication | ❌ | Repeated identical tool calls not filtered |

**Distance to goal: Significant.** The agent currently can't reliably complete the most basic task of understanding a project's file structure. We need to fix the strategy, context injection, error recovery, and path handling before tackling more advanced capabilities.

---

## Recommended Plan

### P0 — Fix Immediately

1. **Fix Agent Strategy: Discover, Don't Guess**
   - Before any `read_file` calls, the agent MUST call `list_files` or `get_project_structure` to discover the actual project layout
   - Implement in the planner prompt: "Always discover the project structure before attempting to read specific files"
   - Alternative: Auto-inject project file listing into the initial context

2. **Auto-Inject RAG Context into Every Agent Request**
   - `EditorAIContextBuilder` should include a file tree overview from the codebase index
   - At minimum, provide the list of top-level directories and key files
   - This eliminates the model's need to guess

3. **Fix Tool Loop: Detect and Break Repetition Loops**
   - `ToolLoopDeduplication` should detect when the same tool+path fails N times
   - After 2 failures on the same path, force a strategy change (e.g., auto-execute `list_files` and inject results)
   - Currently `deduplicatedToolCalls: 0` even though identical calls were made

### P1 — High Priority

4. **Improve Continuation Recovery**
   - When recovery fires, inject a strong hint: "The files you are trying to read don't exist. Use list_files to discover the actual project structure first."
   - Track `planProgress` and escalate intervention as it stays at 0

5. **Teach Model to Use Relative Paths**
   - Update the tool prompt to emphasize project-relative paths
   - Add PathValidator guidance: "Paths starting with / are treated as absolute. Use relative paths like src/components/Foo.tsx"
   - Or auto-resolve relative-looking absolute paths that start from the project root

6. **Add File Discovery as First Tool Call**
   - When agent mode starts, auto-execute a project structure snapshot and inject it into the first user message
   - This gives the model ground truth about what files exist

### P2 — Next Cycle

7. **Model Reliability Improvements**
   - The local model configuration errors need investigation (gemma4 support, config.json parsing)
   - Consider model fallback: if local model fails N times, offer to switch to remote

8. **Telemetry-Driven Quality Monitoring**
   - Add a quality score per agent run based on: plan completion %, tool error rate, recovery count
   - Surface in UI: "Agent struggling — would you like to provide more guidance?"

### What We Can Do Right Now

The simplest, highest-impact fix that requires NO model changes:

```
In EditorAIContextBuilder.buildContext():
  → Fetch project file listing from CodebaseIndex
  → Include it as a system message: "Project structure:\n  src/\n    components/Login.tsx\n..."
```

This alone would prevent the hallucination problem because the model would see actual file names instead of guessing.
