# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-01-09

### Added

- VS Code-style language indicator in the bottom status bar, displaying the detected language for active files and allowing manual override with persistence.

### Changed

- Refactored codebase to comply with Codacy static analysis rules, including splitting multi-declaration files, reducing initializer parameter counts, and improving error handling.

## [0.2.0] - 2025-12-21

### Added

- Liquid-glass settings UI with tabbed General and AI sections.
- OpenRouter configuration (API key, model selection, autocomplete, latency test).
- System prompt editor to override default AI behavior.
- OpenRouter-backed AI service wired to chat.

### Changed

- Settings menu command now uses a single, iconized entry.

