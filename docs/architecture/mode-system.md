# Mode System: Three-Tier Autonomy Model

## Core Principle

The three modes (Chat, Coder, Agent) differ ONLY in **autonomy level** — how much responsibility the AI takes. They do NOT differ in tool capability. All modes use the same tool execution engine, the same model, the same feedback format.

The difference is behavioral: **how** the AI approaches work, not **what** it can do.

---

## The Multiplier Model

| Tier | Mode | Multiplier | Role | Who Drives | Session Length |
|------|------|-----------|------|-----------|----------------|
| 1 | Chat | 1.5x-2x | Expert advisor | You | Minutes |
| 2 | Coder | 3x-5x | Pair programmer | You (direction) | Minutes-Hours |
| 3 | Agent | 10x+ | Engineering lead | AI | Hours-Days |

---

## Tier 1: Chat

### Purpose
A knowledgeable peer who has full project context and can answer questions, find code, and provide perspective — but never touches your code.

### Scope
- Answer questions about the codebase
- Search code, find references, explain implementations
- Browse the web for documentation or solutions
- Provide code reviews and suggestions
- Help you understand complex code

### Responsibilities
- Maintain full project context (files, index, RAG)
- Answer accurately with references to specific code
- Suggest approaches without implementing them
- Explain tradeoffs and alternatives

### Restrictions
Chat mode explicitly blocks these tools because its purpose is read-only assistance:
- `write_file`, `write_files`, `create_file`, `delete_file`
- `patch_file`, `replace_in_file`
- `run_command`

Every other tool is available: `read_file`, `list_files`, `find_file`, `grep`, `search_project`, `web_search`, `web_browse`, `get_project_structure`, all index/RAG tools.

### Flow
1. User asks a question
2. AI searches/reads/researches
3. AI responds with analysis
4. No planning, no execution, no file mutations

---

## Tier 2: Coder

### Purpose
A pair programming partner who takes direction and implements. You say **what** to do, the AI figures out **how** to do it, plans the approach, executes step by step, and verifies the result.

### Scope
- Implement features, refactor code, fix bugs
- Write tests, add documentation, configure tooling
- Run builds and tests to verify changes
- Multi-step tasks with dependencies
- Research and implement using web resources

### Responsibilities
1. **Plan**: Before starting work, create a structured plan with checklist items
2. **Decompose**: Break tasks into discrete, verifiable steps
3. **Execute**: Work through steps in order, reading before writing
4. **Track**: Mark steps complete as they finish
5. **Verify**: Read files back, run tests, confirm correctness
6. **Complete**: Summarize what was done, what wasn't, and why

### Tool Access
**FULL** — identical to Agent mode. All tools are available:
- Read: `read_file`, `list_files`, `find_file`, `grep`, `search_project`, `get_project_structure`
- Write: `write_file` (new files), `patch_file` (edits), `delete_file`
- Execute: `run_command`
- Web: `web_search`, `web_browse`
- Index: all RAG and index tools

### Flow
1. User gives direction: "Refactor persistence into repository pattern"
2. AI plans: `[ ] Analyze current persistence layer` → `[ ] Design repository interface` → `[ ] Implement repositories` → `[ ] Update consumers` → `[ ] Run tests`
3. AI executes: reads files, creates interfaces, implements repositories, updates callers
4. AI verifies: runs build, checks for errors
5. AI reports: "Done. Created 3 repository files, updated 5 consumer files. Build passes."

### Key Constraint
Coder does NOT make architectural decisions without asking. If a choice impacts the project direction, the AI should present options and ask. Coder follows direction — it does not set direction.

---

## Tier 3: Agent

### Purpose
An engineering lead who can architect and execute entire projects. The AI handles top-level strategy, breaks work into domains, spawns sub-agents with specialized prompts, and tracks delivery end-to-end.

### Scope
- Build entire applications from scratch
- Large-scale refactoring across multiple subsystems
- Research projects with multiple investigation threads
- Legacy migration with phased delivery
- Multi-day development sessions

### Responsibilities
1. **Strategize**: Create top-level architecture plan covering all domains
2. **Delegate**: Spawn sub-agents with dedicated prompts for each domain
3. **Orchestrate**: Coordinate sub-agents, resolve conflicts, merge outputs
4. **Track**: Monitor progress across all workstreams
5. **Deliver**: Ensure complete, working delivery

### Tool Access
**FULL** — identical to Coder mode. Same tools, same execution engine.

### Additional Capabilities (Future)
- Sub-agent spawning with isolated contexts
- Bidirectional communication between orchestrator and sub-agents
- DAG-based task scheduling with dependency resolution
- Background task execution with progress reporting

### Flow
1. User requests: "Build a CRM for a small construction company"
2. AI creates top-level plan: architecture, data model, UI, API, testing, deployment
3. AI spawns sub-agents: one for DB schema, one for API design, one for UI components
4. Sub-agents work in parallel, reporting progress
5. AI orchestrator tracks all delivery, resolves conflicts, reports final status

---

## Implementation Notes

### Engine
All three modes route through the **same ToolLoopHandler** execution engine. There is no separate executor for any mode. The engine adapts behavior based on the mode setting in the request.

### Planning
Both Coder and Agent run through StrategicPlanningNode and TacticalPlanningNode for complex inputs. Chat skips planning entirely.

### Enforcement
Plan adherence is tracked by PlanChecklistTracker and enforced by the DispatcherNode. The loop cannot exit while incomplete checklist items remain (unless the model explicitly marks them as blocked).

### Architecture Reference
See [Planning & Enforcement](planning-enforcement.md) for details on the planning tool and loop enforcer.
