# Agentic IDE

[![CI](https://github.com/jtrefon/ai-ide/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/jtrefon/ai-ide/actions/workflows/ci.yml)
[![Release](https://github.com/jtrefon/ai-ide/actions/workflows/release.yml/badge.svg)](https://github.com/jtrefon/ai-ide/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/jtrefon/ai-ide)](https://github.com/jtrefon/ai-ide/releases)
[![License: MIT](https://img.shields.io/github/license/jtrefon/ai-ide)](https://github.com/jtrefon/ai-ide/blob/main/LICENSE)
[![Issues](https://img.shields.io/github/issues/jtrefon/ai-ide)](https://github.com/jtrefon/ai-ide/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/jtrefon/ai-ide/pulls)

A native (no JS Electron), fully compiled, multi-threaded, hardware accelerated, cross‑platform IDE (macOS via MacCatalyst; Windows optional) with a first‑class agentic coding workflow. It ships a VS Code–inspired UI, an auditable tool "+ agent" system, and a testable, modular core.

- Fast MAUI UI with tabs, terminal, and an Agent panel
- EventBus + structured telemetry (initial implementation)
- Modular core under `src/` and xUnit tests under `xunit/`

## Status

Draft, active development. See `AGENTS.md` for the product and agent spec, and `ARCHITECTURE.md` for repo layout and build instructions.

## Quick start

Prereqs:
- .NET 9 SDK
- macOS: Xcode + .NET MAUI workload for MacCatalyst
- Windows: .NET MAUI workload

Build everything:

```bash
# from repo root
 dotnet restore ide.sln
 dotnet build ide.sln -c Debug
```

Run the MAUI app (MacCatalyst example):

```bash
# Build + run the app for MacCatalyst
 dotnet build -t:Run -f net9.0-maccatalyst ide/ide.csproj
```

Run tests:

```bash
 dotnet test xunit/xunit.csproj -c Debug
```

## Repository layout

```
ide.sln
src/
  Ide.Core/
ide/
  (MAUI app)
xunit/
  (xUnit tests)
```

## UI layout

- __Explorer (left)__: Project/file tree (wired via `IBrowseService`).
- __Center__: Split view
  - __Editor (top)__: File editor surface (wired via `IFileService`).
  - __Terminal (bottom)__: Persistent shell session. Prefers zsh on macOS; uses `script(1)` for PTY-like behavior when available; falls back to bash/sh.
- __AI Chat (right)__: Reserved panel for the conversational agent and actions.
- __No top bars__: Shell flyout (hamburger) and navigation bar are disabled for a clean IDE surface.

### Terminal behavior

- Prefers `/bin/zsh`, then `/bin/bash`, then `/bin/sh`.
- On macOS, tries `/usr/bin/script -q /dev/null <shell> -i` to gain PTY-like behavior so interactive tools act like they are attached to a TTY.
- Sets `TERM=xterm-256color` for better color support.
- Falls back to a redirected-stdio session if `script` is unavailable.

### Interactions

- No buttons in the UI. All file operations are through the native File menu.
- File menu:
  - Open File…
  - Open Project…
  - Save File
  - Save Project (All)
- Terminal auto-starts when the page appears; no manual start/stop buttons.

Shortcuts: Cmd+O and Cmd+S planned for Mac; wired through native menu/shortcuts.

## Features (in progress)

- Agent pane with logs and actions
- Event bus for structured events
- Tooling contracts for search/read/write/patch/run (planned)
- Git integration (planned)
- Indexer + retrieval (planned)

## Contributing

We welcome contributions! Please read:
- `CODE_OF_CONDUCT.md`
- `CONTRIBUTING.md`
- `GOVERNANCE.md`

Open issues with complete repro steps and logs. For security disclosures, follow `SECURITY.md`.

## License

MIT. See `LICENSE`.

## Acknowledgments

- .NET MAUI team and community
- xUnit and the .NET OSS ecosystem
