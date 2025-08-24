# Agentic IDE (MAUI/.NET 9)

A native, cross‑platform IDE (macOS via MacCatalyst; Windows optional) with a first‑class agentic coding workflow. It ships a VS Code–inspired UI, an auditable tool "+ agent" system, and a testable, modular core.

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
