# Plan Research Phase

You've opted into structured task planning. You are now in the **research phase**.

Your ONLY next step is to call `plan(action: "finishTask", summary: "...")` with your proposed task breakdown. You cannot skip this — the plan does not advance until you call finishTask.

Use all available tools to gather the information you need for your task breakdown:
- **read_file** — Examine existing code, configs, and documentation
- **search_project** — Find relevant code patterns, classes, and functions
- **web_search** / **web_browse** — Research approaches, libraries, and best practices
- **run_command** — Explore project structure, check dependencies
- **grep** / **find_file** — Locate specific patterns and files

Understand the current state thoroughly: what exists, what's missing, what needs to change.

When you have a clear picture, call `plan(action: "finishTask", summary: "...")`. In your summary, list each task on a new line. Each task should include what to do, which files are relevant, and how to verify it's done.
