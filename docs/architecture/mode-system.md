# Mode System Architecture

## Overview

The application has three modes. They differ ONLY in **autonomy level** — how much responsibility the AI takes — NOT in tool capability. All modes have access to the same tools. The difference is behavioral.

## Tier 1: Chat (1.5x-2x multiplier)

**Role:** Expert pair programmer who reads over your shoulder, gives advice, finds bugs, suggests improvements.

**Behavior:**
- AI has context of the entire project (files, codebase index, RAG)
- AI can search code, browse the web, read files, and answer questions
- AI CANNOT write files, edit files, delete files, or run commands
- YOU do the coding — AI provides perspective, finds references, suggests approaches
- No planning, no execution tracking — conversational only

**When to use:** Code review, getting unstuck, understanding complex code, exploring unfamiliar libraries, asking "how should I approach this?"

## Tier 2: Coder (3x-5x multiplier)

**Role:** Junior-to-mid engineer who you direct. You say WHAT, AI figures out HOW.

**Behavior:**
- AI has FULL tool access (read, write, edit, search, run commands, browse web)
- AI creates a PLAN with checkboxes before starting
- AI DECOMPOSES tasks, executes step-by-step, tracks progress
- AI follows direction: "refactor persistence into repository pattern" → plan → execute → verify
- AI reads files before editing, prefers patch_file over full rewrites
- AI runs builds/tests to verify changes
- AI completes multi-step tasks without dropping context

**When to use:** Refactoring, implementing features, fixing bugs, writing tests, adding documentation — any task where you want the AI to do the work under your direction.

## Tier 3: Agent (10x+ multiplier)

**Role:** Engineering lead who architects and coordinates an entire project.

**Behavior:**
- AI has FULL tool access (same as Coder — identical toolset)
- AI creates TOP-LEVEL STRATEGY: architecture, UI design, tech stack, infrastructure
- AI SPAWNS SUB-AGENTS with dedicated prompts (e.g., "plan database schema", "design API routes", "write tests")
- AI delegates work across domains and tracks all progress
- AI runs long sessions (overnight, multi-hour) for complex projects
- AI does research, compares approaches, makes architectural decisions

**When to use:** Building entire applications from scratch, large-scale refactoring, research projects, legacy migrations, any multi-day project.

## Key Principle

**Tools are IDENTICAL across Coder and Agent.** Both have access to:
- read_file, write_file, patch_file, delete_file
- list_files, find_file, grep, search_project
- run_command, web_search, web_browse
- get_project_structure

The only difference is HOW the AI behaves:
- **Coder**: You drive. AI follows your direction step by step.
- **Agent**: AI drives. AI decides what to build and how.

## Chat is the Exception

Chat mode explicitly blocks mutation tools (write_file, patch_file, delete_file, run_command) because its purpose is read-only assistance. Everything else (search, browse, read) is available.

## Implementation Notes

- Mode is set before the conversation starts and cannot change mid-conversation
- Chat routes through the proven ToolLoopHandler (same execution engine as Agent)
- Coder routes through the proven ToolLoopHandler (same as Agent — NOT a separate executor)
- Agent adds sub-agent spawning and delegation on top of the same tool loop
- Planning (strategic + tactical nodes) runs for BOTH Coder and Agent when the input looks complex
- Tool feedback format (ToolFeedback envelope) is identical across all modes
