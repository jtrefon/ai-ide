# osx-ide

![CI](https://github.com/jtrefon/ai-ide/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/jtrefon/ai-ide/actions/workflows/release.yml/badge.svg)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/db02c680a7e24b90b6340b027b6ebc93)](https://app.codacy.com/gh/jtrefon/ai-ide/dashboard?utm_source=gh&utm_medium=referral&utm_content=&utm_campaign=Badge_grade)
[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=jtrefon_ai-ide&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=jtrefon_ai-ide)

A native macOS IDE experiment built with SwiftUI and AppKit.

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

### Xcode/SourceKit “false compile errors”

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
