# osx-ide Architectural Debt & Engineering Tracker

This document is the **Single Source of Truth** for all identified architectural flaws, code debt, and engineering improvements. The goal is to reach a **Zero Debt State** through systematic refactoring. This is "0 debt project", any decisions should be resolved prioritising the goal of zero debt, quality of the codebase, and maintainability. Before hanging over a task, always run build to ensure the project is in a good state and regresison free. In case of confusion of what order of tasks to do, always refer to this document, it is already sorted by priority. Never stop working on a task until it is completed, unless you are blocked beyound ability to continue within provided framework.

## 🔴 Priority 0: Critical Stability & Core Architecture

### [ARCH-001] Database Thread Safety (Sendable Violation)

- **Issue**: `DatabaseManager` uses `@unchecked Sendable` while exposing a raw SQLite `OpaquePointer`.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Services/Index/Database/DatabaseManager.swift:19`
- **Risk**: Memory corruption and hard crashes due to concurrent access to the raw pointer.
- **Proposed Fix**: Convert to a Swift `actor`, make `db` pointer `private`, and encapsulate all SQLite calls.
- **Status**: ✅ Completed (Database access is actor-isolated via `DatabaseStore`; unit tests passed)

### [ARCH-002] Plugin System Circularity & Tight Coupling

- **Issue**: `CorePlugin` requires concrete `AppState`, while `AppState` relies on plugin-configured services.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Core/CorePlugin.swift:15`
- **Risk**: Prevents modularization and extraction of features into separate SPM packages.
- **Proposed Fix**: Introduce `IDEContext` protocol; inject this into plugins instead of the monolithic `AppState`.
- **Status**: ✅ Completed (CorePlugin depends on IDEContext; AppState conforms; unit tests passed)

### [ARCH-003] Massive God Object: AppState

- **Issue**: `AppState` coordinates everything from file editing to project sessions and UI state.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Services/AppState.swift`
- **Risk**: High coupling, fragile state transitions, and extreme difficulty in unit testing.
- **Proposed Fix**: Decompose into specialized coordinators (`FileEditorCoordinator`, `WorkspaceCoordinator`) and a lightweight `AppRootCoordinator`.
- **Status**: ✅ Completed (Session persistence/workspace lifecycle/state observation extracted into coordinators; unit tests passed)

### [ARCH-004] Singleton Sprawl (15+ Global Instances)

- **Issue**: Excessive reliance on `.shared` singletons (EventBus, UIRegistry, DependencyContainer, etc.).
- **Risk**: Hidden dependencies, global state side-effects, and "spaghetti" data flow.
- **Proposed Fix**: Transition to pure Dependency Injection; move singletons into the `DependencyContainer` as instance-based services.
- **Status**: ✅ Completed (Removed `.shared` access patterns; container is instance-based and dependencies flow through App bootstrap/AppState; build + unit tests green)

### [ARCH-005] Actor Isolation Inconsistency

- **Issue**: `ConversationManager` is `@MainActor` but spawns background tasks; `OpenRouterAPIClient` is an actor but uses `URLSession.shared` incorrectly.
- **Risk**: Potential race conditions and threading overhead from unnecessary context switching.
- **Proposed Fix**: Review and enforce strict actor boundaries across all service layers.
- **Status**: ✅ Completed (Moved logging/index side-effects to detached tasks; removed default `URLSession.shared` usage from OpenRouter client; build + unit tests green)

---

## 🟠 Priority 1: High Impact Performance & Type Safety

### [PERF-001] UI Render Bottleneck (Narrow Observation)

- **Issue**: `AppState` manually propagates `objectWillChange` from all sub-managers.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Services/AppState.swift:214`
- **Risk**: Every minor change (e.g., cursor move) triggers a full re-render of the entire `ContentView`.
- **Proposed Fix**: Views should observe specific sub-managers directly; remove the top-level observation bottleneck.
- **Status**: ✅ Completed (ContentView no longer observes AppState; views observe specific managers; build + unit tests green)

### [TYPE-001] Command Registry Type Erasure

- **Issue**: `CommandRegistry` uses `[String: Any]` for arguments and `ClosureCommandHandler`.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Core/CommandRegistry.swift:28`
- **Risk**: Runtime crashes on type mismatch; lack of compile-time discovery of command parameters.
- **Proposed Fix**: Implement strongly-typed `Command<T>` where `T` is a specific `Arguments` struct.
- **Status**: ✅ Completed (Added typed `TypedCommand<Args>` API with Codable bridging; migrated Explorer commands; unit tests passed)

### [TYPE-002] UIRegistry AnyView Usage

- **Issue**: Registries use `AnyView` to store heterogeneous UI components.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Core/UIRegistry.swift:14`
- **Risk**: Breaks SwiftUI's view update optimizations; significant performance overhead in large trees.
- **Proposed Fix**: Use typed view providers or a component-based protocol that avoids type erasure.
- **Status**: ✅ Completed (UIRegistry stores view factories; type erasure deferred to render time; build + unit tests green)

### [SOLID-001] Massive SRP Violations in ContentView

- **Issue**: `ContentView` handles window styling, layout logic, and 6+ different overlay states.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/ContentView.swift`
- **Proposed Fix**: Extract `WindowManager`, `OverlayManager`, and `LayoutCoordinator` components.
- **Status**: ✅ Completed (Window + overlay responsibilities extracted; build + unit tests green)

### [TYPE-003] Optional Safety & Nullability Annotations

- **Issue**: Mixed use of force-unwraps (`!`) and implicitly unwrapped optionals in critical paths.
- **Risk**: Runtime crashes on unexpected nil values during initialization or file operations.
- **Proposed Fix**: Remove all force-unwraps; implement safe optional binding and proper error propagation.
- **Status**: ✅ Completed (Removed critical force-unwraps; improved safe binding; build + unit tests green)

---

## 🟡 Priority 2: Technical Debt & DRY Violations

### [CLEAN-001] Path Validation Logic Duplication

- **Issue**: `PathValidator` is instantiated ad-hoc in `ConversationManager`, `CorePlugin`, and `TerminalTools`.
- **Proposed Fix**: Centralize in `WorkspaceService` and inject via protocol.
- **Status**: ✅ Completed (Centralized PathValidator creation via WorkspaceServiceProtocol; updated call sites; build + unit tests green)

### [DEBT-001] Regex-Based Swift Parsing

- **Issue**: `SwiftParser` uses fragile regex patterns for symbol extraction.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Services/Index/Parsing/SwiftParser.swift`
- **Risk**: Inaccurate symbols in complex code (nested types, property wrappers).
- **Proposed Fix**: Replace language-specific parsing in core with a **capability-based language module API** for symbol extraction (outline/index/navigation), with deterministic best-effort fallbacks. No single-language exceptions and no vendor parser dependencies embedded as required core dependencies.
- **Status**: ✅ Completed (All symbol extraction now routes through `LanguageModule.symbolExtractor`; removed non-module fallback parsing (`WorkspaceSymbolParser`); build + unit tests green)

### [DEBT-002] Persistence Sprawl (UserDefaults)

- **Issue**: Direct `UserDefaults.standard` access in 11+ files.
- **Proposed Fix**: Create a `SettingsStore` abstraction with typed keys and reactive updates.
- **Status**: ✅ Completed (Introduced SettingsStore wrapper; migrated remaining UserDefaults.standard call sites; build + unit tests green)

### [UI-002] Overlay Component Duplication

- **Issue**: 6+ identical overlay implementations in `ContentView`.
- **Proposed Fix**: Extract a reusable `OverlayContainer` component with standard backdrop/padding.
- **Status**: ✅ Completed (Extracted reusable `OverlayContainer`; migrated all overlays; build + unit tests green)

### [ARCH-006] Protocol Extension Type Casting

- **Issue**: `WorkspaceServiceProtocol` and `FileEditorServiceProtocol` rely on force-casting `objectWillChange` to `ObservableObjectPublisher`.
- **Context**: `@/Users/jack/Projects/osx/osx-ide/osx-ide/Services/ServiceProtocols.swift:22`
- **Risk**: Potential runtime crash if protocols are adopted by non-ObservableObject types.
- **Proposed Fix**: Refactor state observation to use explicit publishers without force casting.
- **Status**: ✅ Completed (Replaced unsafe `as! ObservableObjectPublisher` force-casts with safe `AnyPublisher<Void, Never>` derived from `objectWillChange`; build + unit tests green)

---

## 🟢 Priority 3: Minor Cleanup & Maintenance

### [MAINT-001] Standardize Error Handling

- **Issue**: Inconsistent use of `ErrorManager` vs throwing vs `Result`.
- **Proposed Fix**: Standardize on `Result<T, AppError>` for all asynchronous service calls.
- **Status**: ✅ Completed (Added `Result<T, AppError>` wrappers for core async surfaces including AIService, CommandRegistry, and CodebaseIndex; build + unit tests green)

### [MAINT-002] WAL Mode Contention

- **Issue**: Potential for long-running index transactions to block UI reads.
- **Proposed Fix**: Implement batched, non-blocking transactions in `IndexerActor`.
- **Status**: ✅ Completed (Symbol writes are batched with yielding between batches via `DatabaseStore.saveSymbolsBatched`; `IndexerActor` uses batched path; build + unit tests green)

### [TOOLING-001] Xcode/SourceKit Index Out-of-Sync (False Compile Errors)

- **Issue**: Xcode/SourceKit sometimes reports missing types/compile errors (e.g., `RegexLanguageModule` in `JSONModule.swift`) while `xcodebuild build` and `xcodebuild test` are green.
- **Risk**: Wasted time chasing non-existent build breaks; reduced trust in IDE diagnostics.
- **Proposed Fix**: Document a reliable recovery procedure (DerivedData purge, restart Xcode, re-resolve packages), and prefer `xcodebuild` output as source of truth. Investigate project settings / SPM integration if it recurs.
- **Status**: ✅ Completed (Documented recovery procedure in README; build + unit tests green)

### [DEBT-003] Magic Numbers & Strings

- **Issue**: Hardcoded layout constants and UserDefaults keys.
- **Proposed Fix**: Centralize in `AppConstants`.
- **Status**: ✅ Completed (Centralized editor fonts, overlay/layout constants, settings UI constants, debounce values, and settings keys into `AppConstants`; migrated call sites; build + unit tests green)

### [DEBT-004] TODO Comments & Stubs

- **Issue**: Numerous incomplete features marked with TODO (e.g., CodeEditorView selection passing, UIService stubs).
- **Proposed Fix**: Implement required functionality or remove if obsolete to prevent debt accumulation.
- **Status**: ✅ Completed (Removed/implemented remaining TODO stubs in core surfaces; build + unit tests green)

---

**Last Updated: Jan 8, 2026**
