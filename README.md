# osx-ide

![CI](https://github.com/jtrefon/ai-ide/actions/workflows/ci.yml/badge.svg)
![Release](https://github.com/jtrefon/ai-ide/actions/workflows/release.yml/badge.svg)

A native macOS IDE experiment built with SwiftUI and AppKit.

## Requirements
- macOS 14+
- Xcode 17+

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

## Notes
- The embedded terminal uses the system shell (`/bin/zsh` or `/bin/bash`).
- If spawning a shell fails, grant the app Full Disk Access in System Settings.
