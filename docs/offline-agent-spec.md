# Project: On-Device Assistant + Repo Understanding (macOS / Swift / MLX)

## 0) One-line goal

Deliver **fast, private, offline-capable** inline assistance (FIM completions, quick suggestions, light refactors, code Q&A) by pairing **Granite 4.0 Micro (local)** with a **native retrieval/indexing layer** (tree-sitter + optional LSP + hybrid search).

Granite 4.0 is explicitly positioned for code tasks including **FIM**, **tool usage**, and **structured JSON**, released under **Apache 2.0**.

---

## 1) Scope

### In-scope (v1)

1. **Local inference runtime (MLX)** for Granite 4.0 Micro Instruct.
2. **Model distribution** post-install (downloaded weights, not shipped inside app bundle by default).
3. **Inline code completion (FIM)** + short “chat” actions for:

   * inline suggestions
   * explain error/diagnostic
   * small refactor proposals (apply only with confirmation)
   * quick repo Q&A via retrieval
4. **Repo understanding system**:

   * incremental indexing
   * hybrid retrieval (lexical + embeddings + structural)
   * context assembly + budget control

### Not in-scope (v1)

* LoRA / fine-tuning pipeline (explicitly deferred)
* multi-agent long-horizon execution inside the IDE
* running compilers/builds (unless you already have it; not required for assistant)

---

## 2) Target platform & constraints

* **Target machine**: MacBook Pro M4, **16GB unified memory**
* **OS**: macOS 14+ (recommended; ML/embedding APIs also align here)
* **Latency targets**:

  * Inline suggestion (short completion): **P95 < 250ms time-to-first-token** (when model already loaded)
  * “Explain / Summarize diagnostics”: P95 < 2.5s for typical file context
* **Memory**:

  * Keep total AI subsystem (model + caches + indexes) under **~6–8GB** typical
  * Degrade gracefully (smaller context, fewer retrieved chunks, shorter generations)

---

## 3) Model decision (locked for v1)

### Primary model

* **`ibm-granite/granite-4.0-micro`** (instruct)
* Rationale:

  * Supports **tool calling** + **structured JSON** + **RAG workflows** + **FIM** completion patterns 
  * Apache 2.0 (commercial-friendly)

### FIM format (mandatory)

Use Granite’s documented FIM tags:

* `<|fim_prefix|> ... <|fim_suffix|> ... <|fim_middle|>`

### Quantization strategy (practical)

* **Default shipped option**: 4-bit quant (smallest footprint)
* **Optional “quality mode”**: 8-bit quant

Implementation note: official MLX community conversions exist (often 8-bit), but for full control and repeatability you should **produce your own MLX quant artifacts** via a pinned conversion pipeline, then publish them to your own CDN / HF repo. MLX ecosystem supports this workflow; you’re not inventing fire. 

---

## 4) Model runtime: MLX Swift LM

### Library choice

Use **MLX Swift LM** for local inference plumbing + token streaming.

### Core requirements

* Streaming token output
* Cancellation (per request)
* Model warm pool (keep 1 loaded instance; optionally 2 with different KV-cache policies)
* Deterministic settings per task (temperature=0 for lint/edits; slightly >0 for brainstorming)

### Concurrency model (Swift)

* Use **Actors** for:

  * `ModelRuntimeActor` (model lifecycle + inference)
  * `IndexingActor` (index writes)
  * `RetrievalActor` (query → candidates → rerank → context pack)
* Every user action returns a **CancelableTaskHandle**.

---

## 5) Model distribution: download weights after install

You have two viable tracks:

### Track A (recommended for App Store distribution): Background Assets

Use **Background Assets** to fetch large model files from your CDN / managed asset packs, prefetchable and resumable, and intended specifically for “download additional assets” use-cases.

**Spec requirements**

* Model artifacts are **never required** for first launch (app must still open and function without them)
* Support:

  * auto-download on Wi-Fi + power
  * manual “Download model now” button
  * pause/resume/cancel
* Maintain a **manifest**:

  * version
  * files + sizes
  * sha256
  * quant type (4-bit/8-bit)
  * minimum app version
* Store models in:

  * `~/Library/Application Support/<YourIDE>/Models/<modelId>/<version>/...`
* Integrity:

  * sha256 verify before activation
  * atomic “activate version” switch (symlink or version pointer)

### Track B (non–App Store or fallback): URLSession background downloads

If Background Assets is not usable in some distribution channel, use URLSession background configuration. (Still keep the same manifest + integrity checks.)

---

## 6) Repository understanding architecture (no LoRA)

You’re right to worry about “context being expensive.” The answer is: **don’t brute-force the context window**—build a retrieval layer that feeds the model only what it needs.

This design is a practical hybrid of:

* **RAG** (dense/lexical retrieval + injected evidence) 
* **RepoCoder-style iterative retrieve→generate** for repo-level code completion (retrieval done in rounds, not once) 
* **Hierarchical summaries** (RAPTOR-like) so you can answer “what is this repo?” without dumping raw code

### 6.1 Index types (3 layers)

#### Layer 1: Structural index (fast, always available)

Use **tree-sitter** for incremental parsing and robust syntax trees on every keystroke scale. 

Store:

* file → language
* top-level declarations (functions/classes/imports)
* symbol spans (name, kind, byte range)
* “chunk boundaries” aligned to AST nodes (function/class blocks)

#### Layer 2: Semantic index (optional, deeper accuracy)

Add an internal **LSP client** per workspace when a server exists for the language. LSP is JSON-RPC between editor and language server.

Use LSP to obtain:

* diagnostics
* hover/docstrings
* go-to-definition
* references
* rename/code actions (read-only in v1; apply only with confirmation)

#### Layer 3: Retrieval index (lexical + embeddings)

Two retrieval modes:

1. **Lexical (BM25/FTS)** — best for exact symbol names, strings, error messages
2. **Embeddings** — best for “where is the auth flow implemented?” style questions

**Embeddings provider options (choose one for v1)**

* **Option A (native Apple, lowest dependency): NLContextualEmbedding** (on-device embeddings for natural language)
  *Note:* Great for natural language + docs; not always ideal for code semantics.
* **Option B (recommended for code usefulness): small open embedding model in MLX** (bge-small class models exist in MLX form) 
  This is the “more accurate for code” route.

**Spec decision for v1**

* Use **hybrid retrieval**:

  * lexical first
  * embeddings second
  * merge + dedupe + rerank

---

## 7) Data storage (native, efficient, inspectable)

### Storage engine

* **SQLite** (direct or via a lightweight Swift wrapper)
* Use:

  * FTS5 table for lexical search
  * regular tables for symbols/chunks/embeddings

### Core tables (minimum)

* `files(id, path, lang, hash, mtime, size)`
* `symbols(id, file_id, name, kind, start, end, container, signature)`
* `chunks(id, file_id, start, end, chunk_type, summary_small, summary_large)`
* `fts_chunks(chunk_id, content)`  (FTS5)
* `embeddings(chunk_id, vector BLOB, dim, model_id)`  (only if using embedding retrieval)
* `workspace_state(last_indexed_commit, last_scan_time, schema_version)`

### Index invalidation rules

* file mtime/hash change → re-parse tree-sitter → update symbols/chunks
* embedding index update can be async (stale embeddings allowed for a short window)

---

## 8) Retrieval pipeline (the “brains”)

### 8.1 Query inputs

A retrieval request includes:

* user intent (completion vs Q&A vs fix)
* current file path
* cursor range / selection
* open files list
* language
* optional error diagnostics list (from LSP/build)

### 8.2 Candidate generation

1. **Locality bias**:

   * current file chunk(s)
   * same directory
   * recently edited files
2. **Lexical search**:

   * FTS query terms: identifiers, error messages, function names
3. **Embedding search** (if enabled):

   * query = user question + local code summary
4. **Symbol graph boost**:

   * if LSP available: definition/reference targets outrank everything else

### 8.3 Reranking (cheap)

Use a deterministic reranker:

* overlap with current symbol context
* same module/package
* recency
* “definition/reference” priority
* cap per file to avoid context spam

### 8.4 Context packing (critical)

**Never** dump raw chunks blindly. Pack in this order:

1. “You are here” snippet (±200–400 lines around cursor, trimmed)
2. Relevant symbol signatures (not full bodies)
3. Top K retrieved chunks (trimmed to AST boundaries)
4. Repo summaries (only if needed):

   * project-level summary
   * folder summaries
   * file summaries

This is exactly the kind of iterative retrieval/generation loop shown effective for repo-level completion tasks.

### 8.5 Iterative mode (RepoCoder-style)

For “complete a function using repo context”:

* Round 1: retrieve signatures + nearest deps → generate plan
* Round 2: retrieve specific impl chunks mentioned in the plan → generate completion

---

## 9) Tool calling & safety

Granite supports tool calling and structured outputs; use this to keep the model honest and your IDE deterministic.

### 9.1 Tool API: principles

* Tools are **pure functions** over the workspace state.
* Tools must return **bounded output** (max bytes / max rows).
* Tools must be **side-effect free** in v1, except:

  * `apply_patch` / `apply_edits` which **always requires user confirmation**.

### 9.2 Minimum tool set (v1)

Read-only:

* `read_file(path, range?)`
* `list_files(glob?, limit)`
* `search_text(query, limit, scope?)`
* `search_symbols(name, kind?, limit)`
* `get_symbol_definition(symbolId)` (or LSP-based)
* `get_references(symbolId, limit)`
* `get_diagnostics(file?)` (LSP-based if available)

Write (confirmation required):

* `apply_unified_diff(diffText)`
* `apply_text_edits(file, edits[])`

### 9.3 Output contract

All model-invoked tool calls must produce:

* tool name
* arguments (JSON)
* tool result (JSON)
* then a final assistant message

---

## 10) Prompting templates (production, not vibes)

### 10.1 System prompt (local model)

* Explicitly state:

  * you are inside an IDE
  * you must use tools for repo questions
  * you must not hallucinate file contents
  * you must output edits only as diff when requested

### 10.2 Completion prompt (FIM)

Use Granite FIM tags exactly. 

Template:

* prefix = code before cursor
* suffix = code after cursor
* include a tiny “style header” (language, indent, conventions)
* generation constraints:

  * stop tokens: `\n\n` or language-aware sentinel
  * max tokens tight (e.g., 64–256)

### 10.3 “Fix diagnostic” prompt

* provide:

  * diagnostics list (message, range, severity)
  * minimal code window around each
* require output:

  * either explanation
  * or diff proposal + confidence

---

## 11) UX requirements

### Settings panel

* Local model:

  * Off / On
  * Model variant: 4-bit / 8-bit
  * Download / delete models
  * Disk usage
* Privacy toggle:

  * “Allow remote model fallback” (default: off for privacy purists; on for convenience users)
* Indexing:

  * enable embeddings
  * rebuild index
  * show status (files indexed, last run, errors)

### Inline UI

* Ghost text suggestions
* Accept / reject
* “Explain” button near diagnostics
* “Ask about this repo/file/selection” context menu

---

## 12) Performance & quality guardrails

### Hard limits

* Max context bytes per request (configurable)
* Max retrieved chunks (e.g., 12)
* Max per-file contributions (e.g., 2 chunks)

### Quality protections (small model reality)

* For edit proposals:

  * require model to cite which retrieved chunks it used (by id/path)
  * if it can’t cite, it must ask to retrieve more
* For uncertain answers:

  * force a tool call before responding

---

## 13) Testing plan (must-have)

### Unit tests

* FIM prompt builder correctness
* Tool schemas validation
* Context packer budget compliance
* SQLite migrations + index integrity

### Integration tests

* Index a medium repo (5–20k files):

  * indexing completes
  * incremental updates work
* Retrieval sanity:

  * symbol search returns expected definitions
* Model runtime:

  * cancellation works
  * concurrent requests don’t deadlock

### Golden tests (quality)

Curate ~30 tasks:

* “complete function using helper in another file”
* “explain this error”
* “where is X implemented”
  Score:
* compile/lint pass rate (where applicable)
* edit correctness (applies cleanly)
* hallucination rate (must be near zero when tools available)

---

## 14) Rollout plan (safe)

### Phase 1: plumbing

* MLX runtime loads model + streams output
* UI: “Local model ready” indicator
* No retrieval yet; only local file context

### Phase 2: indexing + lexical retrieval

* tree-sitter chunks + FTS search
* tool calls enabled (read-only)

### Phase 3: embeddings + hybrid retrieval

* embedding index background build
* reranking + context packing

### Phase 4: iterative retrieval for repo completion

* RepoCoder-style 2-round pipeline 

---

## 15) Definition of Done (v1 acceptance criteria)

1. User can **download Granite model** after install; integrity verified; model loads successfully. 
2. Inline FIM completion works using Granite tags; stable latency under typical editing. 
3. Index builds and updates incrementally using tree-sitter.
4. Repo Q&A uses tool calls + retrieval (no hallucinated file contents). 
5. Any file modifications require explicit user confirmation.
6. System remains responsive during indexing (background priority, cancelable).

---

## 16) Practical notes for your “agentic IDE” implementer

If you feed this spec into an implementation agent, include these two extra constraints:

* **Pin everything**: MLX Swift LM commit/tag, model artifact versions, schema version.
* **Instrument early**: token/sec, time-to-first-token, retrieval time, index time, memory pressure events.

---
## 17) Tool schemas and runtime protocol

This section defines the **exact tool contract** the local Granite model will use. It’s designed to be **small-model friendly**, deterministic, and safe.

### 17.1 Tool calling protocol (local, MLX-friendly)

#### 17.1.1 Canonical tool-call model (IDE internal)

The IDE uses a single canonical internal representation for tool calling across providers:

* Assistant responses may include **`toolCalls`** as an array of OpenAI-style tool call objects.
* Each tool call contains:
  * `id`
  * `type` (default: `function`)
  * `function.name`
  * `function.arguments` (JSON string)

This canonical representation is required so the IDE can reuse a single tool execution loop, QA, logging, and orchestration flow across:

* remote providers (e.g. OpenRouter)
* local providers (MLX runtime)

Local-model-specific formats must be adapted into this canonical representation.

#### 17.1.2 Local model output formats (adapter required)

Your runtime will support two assistant output “modes”:

**A) Tool call (machine-readable JSON)**

* The assistant must output **a single JSON object** as the *entire* response.
* The object must match:

```json
{
  "type": "tool_call",
  "calls": [
    {
      "id": "call_1",
      "name": "search_text",
      "arguments": { "query": "AuthToken", "limit": 20 }
    }
  ]
}
```

**B) Final response (plain text OR diff JSON)**

* If output does **not** parse as a `type=tool_call` JSON object, treat it as the final assistant response (plain text).
* For edit proposals, prefer **unified diff text** unless the UI requests structured edits.

Adapter requirement:

* When the local model outputs the `type=tool_call` wrapper JSON, the runtime must translate it into the canonical tool-call array used by the IDE.
* The runtime must not introduce a second tool-loop or a separate execution engine.

#### Tool result injection back to model

After executing tool calls, feed results to the model as:

```
<tool_result id="call_1" name="search_text">
{...json tool result...}
</tool_result>
```

Then prompt the model again with the conversation + appended tool results.

---

### 17.2 Tool result envelope (mandatory)

Every tool returns a JSON object with this envelope:

```json
{
  "ok": true,
  "data": {},
  "error": null,
  "meta": {
    "truncated": false,
    "bytes": 12345,
    "warnings": []
  }
}
```

Rules:

* `ok=false` → `error` must be a stable string code (see below).
* Tool output must be bounded:

  * hard cap: `meta.bytes <= 200_000` (200KB) per tool call
  * if exceeded, set `meta.truncated=true` and trim output.

Standard error codes:

* `invalid_arguments`
* `not_found`
* `permission_denied`
* `requires_confirmation`
* `too_large`
* `internal_error`

---

### 17.3 Confirmation token (write safety)

The IDE enforces write safety using a **confirmation token** minted by the UI layer (not the model). The model never mints tokens.

Write behavior is policy-driven:

* Default policy: write-like tools stage changes (patch set / diff proposal) and return a proposed change without directly mutating the workspace.
* Optional policy (advanced): allow autonomous writes in Agent mode. When enabled, the UI/runtime may mint tokens automatically to allow direct application.

Token semantics:

* single-use
* scoped to workspace + time window (e.g., 60 seconds)
* optionally scoped to a specific diff hash

---

### 17.4 Tool catalog (OpenAI-style schema + local constraints)

Below is the canonical list of tools. You can implement them as local Swift functions; the “schema” below is to keep arguments consistent and to enable future cloud parity.

> **Note:** Even though Granite supports OpenAI-style tools, we’re using the **JSON tool_call wrapper** (17.1) because it’s simplest for an MLX local pipeline.

#### 17.4.1 Read-only tools

```json
[
  {
    "name": "read_file",
    "description": "Read a slice of a text file. Use this to fetch exact code instead of guessing.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "start_line": { "type": "integer", "minimum": 1 },
        "end_line": { "type": "integer", "minimum": 1 },
        "max_bytes": { "type": "integer", "minimum": 1024, "maximum": 200000, "default": 50000 }
      },
      "required": ["path", "start_line", "end_line"]
    }
  },
  {
    "name": "list_files",
    "description": "List files in the workspace. Use glob to narrow. Never request the entire repo at once.",
    "parameters": {
      "type": "object",
      "properties": {
        "glob": { "type": "string", "description": "e.g. **/*.swift" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 500, "default": 200 },
        "include_hidden": { "type": "boolean", "default": false }
      },
      "required": []
    }
  },
  {
    "name": "search_text",
    "description": "Lexical search across indexed content (FTS/BM25). Best for identifiers and error messages.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": { "type": "string" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "default": 30 },
        "paths": {
          "type": "array",
          "items": { "type": "string" },
          "description": "Optional path prefix filters"
        }
      },
      "required": ["query"]
    }
  },
  {
    "name": "search_symbols",
    "description": "Search the symbol index (tree-sitter and/or LSP harvested).",
    "parameters": {
      "type": "object",
      "properties": {
        "name": { "type": "string" },
        "kind": { "type": "string", "description": "function|class|struct|enum|protocol|var|typealias|module|any", "default": "any" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 100, "default": 20 }
      },
      "required": ["name"]
    }
  },
  {
    "name": "get_symbol_definition",
    "description": "Get the definition location and signature for a symbol id.",
    "parameters": {
      "type": "object",
      "properties": {
        "symbol_id": { "type": "string" }
      },
      "required": ["symbol_id"]
    }
  },
  {
    "name": "get_references",
    "description": "Get references/uses for a symbol id.",
    "parameters": {
      "type": "object",
      "properties": {
        "symbol_id": { "type": "string" },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "default": 50 }
      },
      "required": ["symbol_id"]
    }
  },
  {
    "name": "get_diagnostics",
    "description": "Get diagnostics for a file or workspace. Source: LSP and/or internal analyzers.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": { "type": "string", "description": "Optional. If missing, returns workspace diagnostics summary." },
        "limit": { "type": "integer", "minimum": 1, "maximum": 200, "default": 50 }
      },
      "required": []
    }
  },
  {
    "name": "retrieve_context",
    "description": "Hybrid retrieval (lexical + embeddings + structural boosts) returning curated chunks and summaries.",
    "parameters": {
      "type": "object",
      "properties": {
        "query": { "type": "string" },
        "current_path": { "type": "string" },
        "language": { "type": "string" },
        "max_chunks": { "type": "integer", "minimum": 1, "maximum": 20, "default": 8 },
        "max_total_bytes": { "type": "integer", "minimum": 4096, "maximum": 200000, "default": 60000 }
      },
      "required": ["query", "current_path", "language"]
    }
  }
]
```

#### 17.4.2 Write tools (confirmation required)

```json
[
  {
    "name": "apply_unified_diff",
    "description": "Apply a unified diff patch. Requires confirmation_token.",
    "parameters": {
      "type": "object",
      "properties": {
        "diff": { "type": "string" },
        "confirmation_token": { "type": "string" }
      },
      "required": ["diff", "confirmation_token"]
    }
  },
  {
    "name": "apply_text_edits",
    "description": "Apply structured text edits to a file. Requires confirmation_token.",
    "parameters": {
      "type": "object",
      "properties": {
        "path": { "type": "string" },
        "edits": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "start_line": { "type": "integer", "minimum": 1 },
              "start_col": { "type": "integer", "minimum": 0 },
              "end_line": { "type": "integer", "minimum": 1 },
              "end_col": { "type": "integer", "minimum": 0 },
              "replacement": { "type": "string" }
            },
            "required": ["start_line", "start_col", "end_line", "end_col", "replacement"]
          }
        },
        "confirmation_token": { "type": "string" }
      },
      "required": ["path", "edits", "confirmation_token"]
    }
  }
]
```

---

## 18) Prompt pack (exact templates)

### 18.1 System prompt (local model)

Use this for all “chat-style” tasks (diagnostics, repo Q&A, refactor proposals). Keep it *short*, strict, and repetitive about tool usage (small models benefit from redundancy).

```text
You are an on-device coding assistant running inside a macOS IDE.

Hard rules:
- Do NOT guess file contents. If you need code, use tools like read_file, search_text, search_symbols, retrieve_context.
- If asked about the repository, use retrieve_context and/or search_* tools before answering.
- Keep answers concise and technical. Prefer actionable steps.
- When proposing code changes, output a unified diff. Do not apply changes yourself.
- Never request the entire repository. Fetch only what you need.

Tool calling:
- If you need tools, respond ONLY with a single JSON object:
  {"type":"tool_call","calls":[{"id":"call_1","name":"tool_name","arguments":{...}}]}
- Otherwise respond with plain text or a unified diff.

Safety:
- If you are not confident because context is missing, call tools to obtain it.
```

### 18.2 Tool-use “nudge” prefix (optional but recommended)

For tasks that frequently require retrieval, prepend this small prefix right before the user request:

```text
Reminder: Before answering repo questions, call retrieve_context or search_* tools to gather evidence.
```

### 18.3 FIM completion prompt template (Granite FIM)

This is used for inline suggestions and completions. You do **not** use tool calling here. Keep generation short.

```text
You are completing code. Produce only the code that belongs at the cursor. Do not add explanations.

Language: {{LANG}}
Indent: {{INDENT_STYLE}}
File: {{RELATIVE_PATH}}

<|fim_prefix|>
{{PREFIX_CODE}}
<|fim_suffix|>
{{SUFFIX_CODE}}
<|fim_middle|>
```

**Stop conditions (choose per language):**

* Always stop at:

  * `\n\n` (double newline) OR
  * a language-specific sentinel if you insert one (optional)
* Also stop on:

  * `</|fim_middle|>` if your runtime defines it (optional; not required)

**Generation parameters (defaults):**

* `temperature = 0.2`
* `top_p = 0.9`
* `max_new_tokens = 128`
* `repeat_penalty = 1.05` (light)

### 18.4 “Explain diagnostic” prompt template

```text
You are helping diagnose a build/lint issue.

Context:
- Language: {{LANG}}
- File: {{RELATIVE_PATH}}
- Diagnostics:
{{DIAGNOSTICS_JSON}}

Relevant code (may be partial):
{{CODE_SNIPPET}}

Task:
1) Explain the likely cause in 2-4 sentences.
2) Provide the smallest safe fix.
3) If the fix requires other files or definitions, call tools first.
If you propose a fix, output it as a unified diff.
```

### 18.5 Repo Q&A prompt template (retrieval-first)

```text
User question:
{{USER_QUESTION}}

You must gather evidence from the repo before answering.
Call retrieve_context with a focused query derived from the question and current file.
If more detail is needed, call read_file for specific slices.

Answer with:
- a short direct answer
- then 2-6 bullet points of supporting evidence, each referencing file path + line range if available
```

### 18.6 Refactor proposal prompt template (minimal edits)

```text
You are proposing a refactor. Make minimal changes.

Goal:
{{REFACTOR_GOAL}}

Constraints:
- Keep behavior identical unless stated otherwise.
- Prefer small diffs.
- If you need more context, call retrieve_context or read_file.
- Output only a unified diff.

Current file context:
{{CODE_SNIPPET}}
```

### 18.7 Decoding presets (per task)

**Completion (FIM)**

* temp 0.2, top_p 0.9, max_tokens 128

**Diagnostics fix / refactor**

* temp 0.0–0.2, top_p 0.9, max_tokens 512
* require diff output if editing

**Repo Q&A**

* temp 0.2, top_p 0.9, max_tokens 512
* retrieval-first; cite file/lines when possible

---

## 19) SQLite schema and migrations

This schema supports:

* file tracking + incremental updates
* symbols + chunking
* lexical search (FTS5)
* optional embedding vectors (stored efficiently)

### 19.1 Core SQLite schema (DDL)

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

-- Track schema version
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR IGNORE INTO meta(key, value) VALUES ('schema_version', '1');

-- Workspace identity (one DB per workspace root)
CREATE TABLE IF NOT EXISTS workspace (
  id INTEGER PRIMARY KEY,
  root_path TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- File registry
CREATE TABLE IF NOT EXISTS files (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL UNIQUE,
  lang TEXT NOT NULL,
  mtime INTEGER NOT NULL,
  size INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  is_binary INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_files_lang ON files(lang);
CREATE INDEX IF NOT EXISTS idx_files_mtime ON files(mtime);

-- Symbol index (tree-sitter and/or LSP)
CREATE TABLE IF NOT EXISTS symbols (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL,
  container TEXT,
  signature TEXT,
  start_line INTEGER NOT NULL,
  start_col INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  end_col INTEGER NOT NULL,
  FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_symbols_name ON symbols(name);
CREATE INDEX IF NOT EXISTS idx_symbols_file ON symbols(file_id);

-- Code chunks aligned to AST nodes
CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY,
  file_id INTEGER NOT NULL,
  chunk_type TEXT NOT NULL, -- function|class|struct|block|doc|other
  start_line INTEGER NOT NULL,
  end_line INTEGER NOT NULL,
  byte_start INTEGER NOT NULL,
  byte_end INTEGER NOT NULL,
  content_sha256 TEXT NOT NULL,
  summary_small TEXT, -- optional
  summary_large TEXT, -- optional
  FOREIGN KEY(file_id) REFERENCES files(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file_id);

-- FTS for lexical search over chunk content
CREATE VIRTUAL TABLE IF NOT EXISTS fts_chunks USING fts5(
  content,
  path UNINDEXED,
  chunk_id UNINDEXED,
  tokenize = 'unicode61'
);

-- Map chunk_id -> fts row via chunk_id column itself (stored UNINDEXED)
-- Maintain fts_chunks rows from app code (insert/update/delete).
```

### 19.2 Embedding storage (efficient, low-footprint)

SQLite alone isn’t great as an ANN vector engine without extensions. The “native” approach is:

* SQLite stores metadata + mapping
* vectors are stored in a **memory-mapped binary file** (`embeddings.dat`)
* optional ANN index stored as `ann_hnsw.bin`

Add these tables:

```sql
-- Embedding model registry (so you can change embedder later)
CREATE TABLE IF NOT EXISTS embedding_models (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE, -- e.g. "bge-small-en-v1.5-mlx-384"
  dim INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);

-- Embedding pointers into embeddings.dat (a binary blob file)
CREATE TABLE IF NOT EXISTS embeddings (
  chunk_id INTEGER PRIMARY KEY,
  model_id INTEGER NOT NULL,
  offset_bytes INTEGER NOT NULL,
  length_bytes INTEGER NOT NULL,
  norm REAL NOT NULL,
  FOREIGN KEY(chunk_id) REFERENCES chunks(id) ON DELETE CASCADE,
  FOREIGN KEY(model_id) REFERENCES embedding_models(id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_embeddings_model ON embeddings(model_id);
```

**Binary format for `embeddings.dat`**

* float32 little-endian, contiguous vectors
* each vector length = `dim * 4` bytes
* store `norm` in SQLite for fast cosine similarity

**Search strategy**

* For small workspaces: brute-force cosine over candidates using Accelerate (fast enough up to ~50k vectors).
* For larger: build/maintain `ann_hnsw.bin` and use ANN lookup to preselect top N, then exact cosine rerank.

### 19.3 Chunking rules (must be deterministic)

Chunk extraction algorithm:

* Prefer AST node boundaries:

  * function/method bodies
  * class/struct blocks
  * module-level blocks
* Size targets:

  * 200–800 tokens of code per chunk (approx; use byte limits)
  * hard clamp by bytes: 2KB–12KB per chunk
* For very large nodes:

  * split by inner blocks (if/guard/switch) but keep stable boundaries

### 19.4 Index update rules (incremental)

On file change:

1. compute sha256
2. if unchanged: do nothing
3. else:

   * delete existing `symbols`, `chunks`, `fts_chunks` rows for file
   * re-parse with tree-sitter
   * reinsert symbols + chunks
   * update `fts_chunks` content rows
   * enqueue embedding generation (async)

### 19.5 Migration policy

* Maintain `meta.schema_version`
* On startup:

  * read schema_version
  * apply migrations sequentially
  * each migration is:

    * an idempotent SQL script
    * followed by a verification query

Example migration skeleton:

```sql
-- migration_001_to_002.sql
BEGIN;
UPDATE meta SET value='2' WHERE key='schema_version';
COMMIT;
```

(Keep real migrations additive; avoid destructive changes without backup.)

---

## 20) Deliverables to hand off to your agentic implementer

### 20.1 Files to create in repo (recommended layout)

```
/AI
  /Model
    ModelManager.swift
    ModelRuntimeActor.swift
    PromptTemplates.swift
    GenerationPresets.swift
  /Tools
    ToolRouter.swift
    ToolSchemas.json
    ToolResultEnvelope.swift
    ConfirmationToken.swift
  /Indexing
    WorkspaceScanner.swift
    TreeSitterParser.swift
    Chunker.swift
    SymbolExtractor.swift
    FTSWriter.swift
    EmbeddingGenerator.swift
    EmbeddingStore.swift
    RetrieverActor.swift
  /Storage
    WorkspaceDB.swift
    Migrations/
      001_init.sql
      002_embeddings.sql
  /Eval
    GoldenSuite.json
    Harness.swift
```

### 20.2 “Airtight” acceptance checks for this continuation

* Tool calls **always** parse or fail safely (never partial execution).
* Write tools **never** run without confirmation token.
* Context packer never exceeds configured budgets.
* Indexer is cancelable and doesn’t freeze UI.
* Model download verifies sha256 and activates atomically.

