# Planning Enforcement (Philosophy: No Enforcement)

## Key Decision

The planning system is **model-chosen, not pipeline-enforced**. The model opts in by calling `plan.init`. Once opted in, the plan tool's responses guide the model through phases, but there is no system-level enforcement.

## What This Means

- The model can ignore the plan at any time
- The plan tool returns guidance, not gates
- There is no block in the ToolLoopHandler that prevents the model from exiting
- The artifact detector defers to the plan (see ToolLoopHandler.swift), but this is a soft check — the plan's `isComplete` prevents premature termination, it doesn't force tasks

## Why No Enforcement

1. **Model trust**: Enforcement fights the model's agency. The model should want to use the plan because it helps, not because it's forced.
2. **Flexibility**: Some requests genuinely don't need a plan. The model should be free to choose.
3. **Prompt-driven**: The "Your ONLY next step is to call finishTask" language in the phase prompts is instruction, not enforcement. The model follows it because the prompts are clear and compelling.
4. **Circuit breakers**: `raiseQuestion` and `breakOutCantContinue` give the model escape routes without needing to abandon the plan entirely.

## What Provides Structure Instead

- **Tool contract**: Once `init` is called, the plan tool returns phase guidance that clearly states the only valid next action
- **Prompt clarity**: "Your ONLY next step is to call finishTask" — unambiguous, no alternatives listed
- **Positive framing**: The tool explains WHY to follow the plan (focus, context, tracking) not WHAT happens if you don't
- **Confinement via value**: Each `finishTask` returns the next task's full context — the model stays because it gets useful information it wouldn't have otherwise
