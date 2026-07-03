# Modes

Three distinct modes. Each is a separate system prompt + tool registry. They share engine infrastructure but are **exclusive** — the model is never told about other modes.

---

## Chat

**Purpose:** Read-only conversation. AI perspective without altering anything.

**Tool access:** All tools **except** file writes/edits/deletes and terminal execution:
- Blocked: `write_file`, `patch_file`, `replace_in_file`, `delete_file`, `create_file`, `run_command`
- Allowed: `read_file`, `list_files`, `find_file`, `grep`, `search_project`, `web_search`, `web_browse`, `get_project_structure`, `plan`

**Behavior:** Answer questions, explain code, analyze architecture, discuss. Never claims it made changes. Never runs commands. Never writes files.

**Prompt:** `Prompts/System/mode-chat.md`

---

## Coder

**Purpose:** Full-access pair programming. The primary working mode. Directly competes with Cursor, Windsurf, Code Pilot.

**Tool access:** **Everything.** All tools, all rights.

**Behavior:** Reads files before editing. Plans multi-step work. Uses `patch_file` for edits (surgical), `write_file` only for new files. Runs commands to build/test. Verifies work. Calls `plan(action: "finishTask", summary: "...")` after each task when using structured planning.

**Structured Task Planning:** Model calls `plan(action: "init")` to opt in. Three phases:
1. **Research** — explore project, gather context
2. **Execution** — one task at a time, call `finishTask` after each
3. **Done** — all tasks complete, framework asks for final summary

**Prompt:** `Prompts/System/mode-coder.md`

---

## Agent

**Status: 🚧 Not yet implemented.** Will be developed once Coder is rock solid. Agent will inherit the full coder engine and tooling.

**Purpose:** Fully autonomous swarm execution. Parallel agent instances for task decomposition and concurrent progress across large-scale work.

**Tool access:** Same as Coder + sub-agent spawning (future).

**Use cases:** Large-scale research, extensive legacy refactoring across many modules, multi-domain work spanning architecture/UI/testing/infra.

**Prompt:** `Prompts/System/mode-agent.md`

---

## Architecture

```
User selects mode in UI
       │
       ▼
ConversationManager.currentMode (AIMode)
       │
       ▼
SystemPromptAssembler loads ONE mode prompt:
  .chat  → Prompts/System/mode-chat.md
  .coder → Prompts/System/mode-coder.md
  .agent → Prompts/System/mode-agent.md
       │
       ▼
AIMode.allowedTools(from:) filters tool registry:
  .chat  → blocks write_file, patch_file, delete_file, run_command, etc.
  .coder → all tools allowed
  .agent → all tools allowed (future)
```

No mode prompt references another mode. Mode-specific code paths are guarded by `mode == .chat` / `.coder` / `.agent` checks. The engine (`ToolLoopHandler`, `SystemPromptAssembler`, tool execution) is shared infrastructure.

---

## ⚠️ Rules

1. **Never add cross-mode references.** A mode prompt must not mention another mode by name or describe its behavior.
2. **Never add mode references in shared prompts.** The base system prompt, tool prompts, and conversation flow corrections must be mode-agnostic.
3. **Keep mode prompts self-contained.** Each file is the single source of truth for that mode's behavior.
4. **Agent inherits from Coder.** When agent is built, it reuses all Coder infrastructure — no duplicate tooling.
