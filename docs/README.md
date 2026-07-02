# osx-ide — AI-Powered IDE Documentation

This directory contains architecture and design documentation for the osx-ide application — an AI-native IDE for macOS.

## Quick Navigation

| Document | Description |
|----------|-------------|
| [Architecture Overview](architecture/README.md) | High-level architecture, component relationships |
| [Mode System](architecture/mode-system.md) | The three-tier autonomy model (Chat/Coder/Agent) |
| [Tool Architecture](tool-architecture-research.md) | Tool execution, feedback format, sandbox |
| [Planning & Enforcement](architecture/planning-enforcement.md) | Planning tool design, loop enforcer, plan adherence |
| [Phase 1 Plan](phase-1-plan.md) | Implementation plan for Phase 1 |

## Core Philosophy

The application is built on a **multi-tier multiplier model** — the same AI capabilities are scaled across three autonomy levels, each providing a different developer experience multiplier.

See [Mode System](architecture/mode-system.md) for the full breakdown.
