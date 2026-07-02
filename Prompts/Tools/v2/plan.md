# plan Tool

## Purpose
Break down complex work into structured, focused tasks. Call `init` to opt in — you commit to completing all tasks, working through them one at a time with full context for each.

## When to Use
- Any task that needs multiple steps, files, or phases
- When you want to architect an approach and follow it with precision
- When you need to maintain focus and track what's been done

## When NOT to Use
- Do NOT use for single-turn tasks you can complete immediately
- Do NOT use when just answering a question or having a conversation

## Available Methods
| Method | When | What happens |
|--------|------|-------------|
| `init` | Start planning | Enters research phase. Use all tools to explore. |
| `finishTask` | End current phase | Research → execution: provide task breakdown. Execution → next: mark task done, advance. |
| `raiseQuestion` | Mid-plan | Pauses for user clarification. |
| `breakOutCantContinue` | Stuck | Aborts plan with reason. |

## Parameters
- **action** (required, string): `"init"` | `"finishTask"` | `"raiseQuestion"` | `"breakOutCantContinue"`
- **summary** (optional, string): For finishTask. During research: your proposed task breakdown. During execution: what was done.
- **question** (optional, string): Required for raiseQuestion.
- **blocker_reason** (optional, string): Required for breakOutCantContinue.
