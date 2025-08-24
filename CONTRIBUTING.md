# Contributing Guide

Thanks for your interest in contributing! This guide explains how to propose changes and how we work.

## Development setup

- Install .NET 9 SDK
- For macOS, install Xcode + MAUI MacCatalyst workload

Build and test:

```bash
 dotnet restore ide.sln
 dotnet build ide.sln -c Debug
 dotnet test xunit/xunit.csproj -c Debug
```

Run the app (MacCatalyst):

```bash
 dotnet build -t:Run -f net9.0-maccatalyst ide/ide.csproj
```

## Workflow

- Fork and create a feature branch: `feat/<slug>` or `fix/<slug>`
- Keep PRs small and focused; add tests for any new logic
- Use Conventional Commits for messages:
  - `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `perf:`
- Follow coding standards in `AGENTS.md` section 20

## Testing

- Unit tests: xUnit in `xunit/`
- Add tests for new code and bug fixes; aim for >80% coverage in core services

## Style & Lint

- Nullable + implicit usings enabled
- Prefer small classes/methods; async/await where applicable

## PR checklist

- [ ] Linked issue
- [ ] Tests added/updated
- [ ] Docs updated (README/ARCHITECTURE/AGENTS as applicable)
- [ ] Follows coding standards

## Communication

- Open issues for bugs/features
- Use discussions (if enabled) for Q&A/ideas

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
