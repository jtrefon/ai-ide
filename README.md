# osx-ide

![CI](https://github.com/jtrefon/ai-ide/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/jtrefon/ai-ide/actions/workflows/release.yml/badge.svg)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/db02c680a7e24b90b6340b027b6ebc93)](https://app.codacy.com/gh/jtrefon/ai-ide/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Bugs](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=bugs)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Code Smells](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=code_smells)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Duplicated Lines (%)](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=duplicated_lines_density)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Lines of Code](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=ncloc)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=reliability_rating)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=security_rating)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Technical Debt](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=sqale_index)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)
[![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=vulnerabilities)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)

**osx-ide** is a cutting-edge, AI-powered Integrated Development Environment (IDE) designed exclusively for macOS. It harmonizes hardware and software to deliver exceptional performance, providing developers with maximum support through embedded AI capabilities and an unparalleled user experience.

Built with SwiftUI and AppKit, osx-ide leverages native macOS technologies to offer seamless integration, lightning-fast responsiveness, and intuitive workflows. Whether you're coding, debugging, or collaborating with AI, osx-ide empowers you to achieve more with less effort.

## Key Features

- **AI-Enhanced Development**: Integrated AI agent for intelligent code assistance, refactoring, and problem-solving with multi-role orchestration (Architect, Planner, Worker, QA).
- **High-Performance Code Editor**: Advanced syntax highlighting, multi-cursor editing, code folding, minimap, and real-time diagnostics with clickable build errors.
- **Intelligent Codebase Indexing**: Fast symbol extraction, search, and navigation across large projects with memory-based context retention.
- **Native Terminal Integration**: Embedded terminal with build error parsing and clickable links to editor locations.
- **Project Session Persistence**: Saves window layout, open tabs, and editor state for uninterrupted workflows.
- **Command-Driven UX**: Comprehensive command palette and menu system for efficient navigation and actions.
- **Extensible Language Support**: Plugin-based architecture for multiple programming languages with best-effort fallbacks.
- **Near-Future Embedded AI**: Planned deep integration of AI for code generation, review loops, and autonomous development tasks.

osx-ide is engineered for the future of software development, where AI and human creativity converge to produce high-quality code faster than ever before.

## Requirements

- macOS 14+
- Xcode 17+

## Development

The project includes a unified `run.sh` script for common development tasks.

```sh
# Build and launch the application
./run.sh app

# Build only
./run.sh build

# Run unit tests
./run.sh test

# Run UI (E2E) tests
./run.sh e2e

# Clean build artifacts
./run.sh clean
```

## Build

Open `osx-ide.xcodeproj` in Xcode and run the `osx-ide` scheme.

Command line build:

```sh
xcodebuild -project osx-ide.xcodeproj -scheme osx-ide -configuration Debug build
```

## Test

```sh
xcodebuild -project osx-ide.xcodeproj -scheme osx-ide -configuration Debug test -destination 'platform=macOS'
```

## Troubleshooting

### Xcode/SourceKit "false compile errors"

Sometimes Xcode/SourceKit can show red errors (missing types, failed imports, etc.) while `xcodebuild build` and `xcodebuild test` are green.

Recovery steps (in order):

1. Quit Xcode.
2. Run `./run.sh clean`.
3. Delete DerivedData for this project:
   - In Finder: `~/Library/Developer/Xcode/DerivedData/` (remove the `osx-ide-*` folder)
4. Re-open `osx-ide.xcodeproj`.
5. In Xcode: `File > Packages > Reset Package Caches` (if needed).
6. Build once from Xcode.

If the issue persists but `xcodebuild` is still green, treat `xcodebuild` output as the source of truth and file an issue with:

- Xcode version
- Steps that reproduce
- A screenshot of the SourceKit error
- Relevant `xcodebuild` output

## Notes

- The embedded terminal uses the system shell (`/bin/zsh` or `/bin/bash`).
- If spawning a shell fails, grant the app Full Disk Access in System Settings.
