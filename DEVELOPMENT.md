# Development Guide

## Environment

- .NET 9 SDK
- macOS: Xcode + MAUI workload for MacCatalyst

## Build

```bash
 dotnet restore ide.sln
 dotnet build ide.sln -c Debug
```

## Run (MacCatalyst)

```bash
 dotnet build -t:Run -f net9.0-maccatalyst ide/ide.csproj
```

## Test

```bash
 dotnet test xunit/xunit.csproj -c Debug
```

## Project structure

- App (`ide/`): MAUI shell, pages, DI registration
- Core (`src/Ide.Core`): domain/services (e.g., Events/EventBus)
- Tests (`xunit/`): xUnit tests referencing core libraries

## Coding standards

See `AGENTS.md` section 20 for enforced standards.

## Commit style

Conventional Commits. Example: `feat: add EventBus and Agent page`
