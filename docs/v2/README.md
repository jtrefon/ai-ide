# v2 Search + RAG Decomposition

> **Status:** Design Complete. Ready for Implementation.
> **Goal:** Split the monolithic `CodebaseIndex` into two independent systems with clear boundaries.
> **Why:** The current system mixes structural code lookup (symbols, FTS) with semantic retrieval (embeddings, chunks, HNSW) in a single SQLite database. This causes slow indexing (minutes instead of seconds), tool confusion for the LLM (14 search tools), and a fragile RAG pipeline with hand-tuned weights.

## The Two Systems

| System | Name | Purpose | Index Speed | ML? |
|--------|------|---------|-------------|-----|
| **Search** | `search_code` | Lightning-fast structured code navigation | ~3-8 seconds | No |
| **Memory** | `project_memory` | Agent-level project knowledge, memories, context | N/A (per-entry) | Optional |

## Documents

| File | What It Covers |
|------|----------------|
| [SPEC.md](SPEC.md) | Product requirements, success criteria, out-of-scope |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture, data flow, component diagram |
| [SEARCH_CODE.md](SEARCH_CODE.md) | `search_code` tool: schema, indexing pipeline, query patterns |
| [PROJECT_MEMORY.md](PROJECT_MEMORY.md) | `project_memory` system: memories, chat summaries, search cache |
| [TOOL_CONTRACTS.md](TOOL_CONTRACTS.md) | Exact tool definitions (JSON schema, parameters, return types) |
| [MIGRATION.md](MIGRATION.md) | Step-by-step migration plan with file changes |

## Key Principles

1. **No ML in the search path.** Code navigation is a structured data problem. Symbols + FTS5 are faster and more precise than embeddings.
2. **Agent memory is not code search.** Store what the agent learns (architecture, decisions, bug fixes), not source code.
3. **Chat summaries, not raw transcripts.** Raw conversations are noisy and bloated. Summaries preserve signal.
4. **Keyword search is sufficient for memory.** At the scale of hundreds of memories, FTS5 works as well as vectors without the complexity.
5. **Tools must be orthogonal.** No overlap between `search_code` and `project_context`. The LLM should never wonder which tool to use.

## Quick Start for Implementers

1. Read [SPEC.md](SPEC.md) first — understand what we're building and why.
2. Read [ARCHITECTURE.md](ARCHITECTURE.md) — understand the big picture.
3. Read [SEARCH_CODE.md](SEARCH_CODE.md) and [PROJECT_MEMORY.md](PROJECT_MEMORY.md) — understand each system.
4. Read [TOOL_CONTRACTS.md](TOOL_CONTRACTS.md) — understand the exact interfaces.
5. Follow [MIGRATION.md](MIGRATION.md) — step-by-step implementation order.
