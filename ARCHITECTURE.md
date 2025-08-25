# Architecture Overview

Status: Stable baseline
Audience: Engineering, Product, QA

---

## Goals

- Desktop-only MAUI IDE (macOS via MacCatalyst; Windows optional on Windows hosts)
- Modular core logic in libraries (DLLs) under `src/`
- Unit tests per library under `tests/` (currently `xunit/`)

---

## Repository Structure

```text
ide.sln
src/
  Ide.Core/
    Ide.Core.csproj
ide/
  ide.csproj
  Platforms/
    MacCatalyst/
    Windows/
xunit/
  xunit.csproj
```

Notes:
- Mobile folders (Android/iOS) are removed from the tree and not targeted by the app.
- The MAUI app (`ide/`) references core libraries (e.g., `src/Ide.Core`).
- Tests reference the libraries directly.

---

## Platforms & Target Frameworks

- App: `net9.0-maccatalyst`
- Conditional on Windows hosts: `net9.0-windows10.0.19041.0`
- No Android/iOS TFMs or SDK workloads required.

---

## Projects

- ide/ide.csproj
  - MAUI app shell and UI
  - References: `src/Ide.Core`
  - Desktop-only targets

- src/Ide.Core/Ide.Core.csproj
  - Pure .NET core services and domain logic
  - Example: `Utils/CounterService`

- xunit/xunit.csproj
  - Unit test project (xUnit)
  - References: `src/Ide.Core`

---

## Build & Test

From repo root:

```bash
# Restore and build whole solution
 dotnet restore ide.sln
 dotnet build ide.sln -c Debug

# Or build core library and run tests only
 dotnet build src/Ide.Core/Ide.Core.csproj -c Debug
 dotnet test xunit/xunit.csproj -c Debug
```

---

## Modularity Plan

- Libraries live under `src/<ModuleName>` (e.g., `Ide.Plugins.*`, `Ide.Domain`, etc.)
- Tests live under `tests/<ModuleName>.Tests` (we will migrate `xunit/` to `tests/` as projects accrue)
- App consumes libraries via `ProjectReference`

---

## Coding & Quality

- Nullable + implicit usings enabled
- Unit tests mandatory for core logic changes
- Prefer DI-friendly designs, small classes/methods
- No blocking calls on UI thread; async/await where applicable

---

## Future Extensions

- Plugin SDK (`Ide.Plugins.*`)
- Indexer, Tool Host, Runner abstraction projects
- CI with test + style analyzers
