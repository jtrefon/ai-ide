# Quality Improvement Tracker

This document tracks technical debt and quality issues identified during the code review, organized by priority.
Please carry on with development with set of priorities:

- quality is paramount, it takes priority over anything else.
- confused what to do next, use order of importance from this document.
- always build after finishing task to catch any compilation errors and ensure regression free state.
- always write tests for new functionality.
- always update this document when completing tasks.

## Legend

- 🔴 **Critical** - High impact, must address soon
- 🟡 **High** - Significant impact, address in next sprint
- 🟢 **Medium** - Moderate impact, address when convenient
- ⚪ **Low** - Minor improvements, address during maintenance

---

## 🔴 Critical Issues (Priority 1)

### 1. AIToolExecutor.executeBatch - Extreme Complexity

**File:** `osx-ide/Services/AIToolExecutor.swift:464-490`
**Metrics:** 21 lines, CCN 11 (reduced from 265 lines, CCN 20)
**Status:** ✅ Completed - ToolArguments migration + tests + thresholds verified
**Estimated Effort:** 1-2 days remaining

**Completed Actions:**

- [x] Introduced `ToolArguments` (@unchecked Sendable) wrapper for JSON-style `[String: Any]` arguments
- [x] Updated `AITool` protocol to accept `ToolArguments` instead of raw `[String: Any]`
- [x] Updated `AIToolProgressReporting` protocol to accept `ToolArguments`
- [x] Updated `AIToolExecutor` to pass `ToolArguments` and use `.raw` internally
- [x] Updated all tool implementations in `Services/Tools` to accept `ToolArguments`
- [x] Updated all test files to use `ToolArguments`
- [x] Extracted `executeToolCall` helper to reduce method length
- [x] Extracted `buildMergedArguments` helper for argument merging
- [x] Extracted `executeToolAndCaptureResult` helper for tool execution
- [x] Extracted `makeToolCallFinalMessage` helper for result message creation
- [x] Extracted `sendToolProgressSnapshot` helper (nonisolated static)
- [x] Extracted `makeToolExecutionMessage` helper (nonisolated static)
- [x] Extracted `makeExecuteBatchTask` helper to reduce `executeBatch` method length
- [x] Removed `@MainActor` from tool protocols and implementations (ToolArguments handles sendability)
- [x] Build succeeded
- [x] Tests passed (42 tests in 3 suites)
- [x] Codacy analysis completed for all edited files

**Remaining Actions:**

- [x] Verify `executeBatch` LOC/CCN stays under configured thresholds (now ~21 LOC)
- [x] Consider extracting additional helpers if complexity remains high
- [x] Write unit tests for extracted components
- [x] Update call sites if needed
- [x] Run tests and verify functionality

---

### 2. CodeFormatter.format - High Complexity

**File:** `osx-ide/Services/Index/Models/CodeFormatter.swift:11-56`
**Metrics:** CCN 18
**Status:** ✅ Completed - Strategy + helper extraction, tests, verification complete
**Estimated Effort:** Completed

**Actions:**

- [x] Extract `BraceAnalyzer` for brace counting logic
- [x] Extract `IndentLevelCalculator` for indent level calculation
- [x] Create per-language formatting strategies using Strategy pattern
- [x] Write unit tests for each component
- [x] Update call sites
- [x] Run tests and verify functionality

---

### 3. Large Files (>500 LOC) - Maintainability Risk

**Status:** 🟡 In Progress
**Estimated Effort:** 5-7 days total

#### 3.1 DatabaseManager.swift (692 LOC)

**File:** `osx-ide/Services/Index/Database/DatabaseManager.swift`
**Actions:**

- [x] Extract schema management to `DatabaseSchemaManager`
- [x] Extract query operations to `DatabaseQueryExecutor`
- [x] Extract AI enrichment operations to `DatabaseAIEnrichmentManager`
- [x] Extract memory operations to `DatabaseMemoryManager`
- [x] Extract symbol operations to `DatabaseSymbolManager`
- [x] Write tests for extracted components
- [x] Update DI container (N/A - extracted helpers are internally constructed by `DatabaseManager`)

#### 3.2 ConversationManager.swift (663 LOC)

**File:** `osx-ide/Services/ConversationManager.swift`
**Actions:**

- [x] Extract chat history management to `ChatHistoryCoordinator`
- [x] Extract AI interaction coordination to `AIInteractionCoordinator`
- [x] Extract tool execution coordination to `ToolExecutionCoordinator`
- [x] Extract tool construction to `ConversationToolProvider`
- [x] Delegate retry logic to `AIInteractionCoordinator.sendMessageWithRetry`
- [x] Delegate tool execution to `ToolExecutionCoordinator.executeToolCalls`
- [x] Extract send/tool-loop orchestration to `ConversationSendCoordinator` (make `ConversationManager` a thin facade)
- [x] Write tests for extracted components
- [x] Update DI container (N/A - coordinator is constructed internally by `ConversationManager`)

#### 3.3 FileEditorStateManager.swift (633 LOC)

**File:** `osx-ide/Services/FileEditorStateManager.swift`
**Actions:**

- [x] Extract file watching logic to `FileWatchCoordinator`
- [x] Extract editing state management to `EditingStateManager`
- [x] Extract tab management to `EditorTabManager`
- [x] Extract language detection to `EditorLanguageDetector`
- [x] Write tests for extracted components
- [x] Update DI container

**Implementation Notes (Patterns):**

- **Facade:** `EditorPaneStateManager` delegates responsibilities to focused components while keeping the public API stable.
- **Coordinator:** `FileWatchCoordinator` owns file watcher lifecycle + debouncing.
- **Strategy:** `EditorLanguageDetecting` (`DefaultEditorLanguageDetector`) handles language detection for untitled buffers and extension mapping.

**New/Updated Files:**

- `osx-ide/Services/EditorLanguageDetector.swift`
- `osx-ide/Services/EditingStateManager.swift`
- `osx-ide/Services/EditorTabManager.swift`
- `osx-ide/Services/FileWatchCoordinator.swift`

**Verification:**

- [x] `./run.sh test`
- [x] Codacy CLI on edited/created Swift files

#### 3.4 CodeEditorView.swift (548 LOC)

**File:** `osx-ide/Components/CodeEditorView.swift`
**Actions:**

- [x] Extract coordinator to `TextViewRepresentable+Coordinator.swift`
- [x] Extract highlighting logic (implemented within `TextViewRepresentable+Coordinator.swift`)
- [x] Write tests for extracted components

#### 3.5 ModernFileTreeView.swift (503 LOC)

**File:** `osx-ide/Components/ModernFileTreeView.swift`
**Actions:**

- [x] Extract data source to `FileTreeDataSource.swift`
- [x] Extract coordinator (search + context menu) to `ModernFileTreeCoordinator.swift`
- [x] Write tests for extracted components

#### 3.6 CodebaseIndex.swift (504 LOC)

**File:** `osx-ide/Services/Index/CodebaseIndex.swift`
**Actions:**

- [x] Extract indexing coordination to `IndexCoordinator`
- [x] Extract symbol operations to `QueryService` / `IndexerActor`
- [x] Extract memory management to `MemoryManager`
- [x] Write tests for extracted components
- [x] Update DI container

#### 3.7 osx_ideTests.swift (607 LOC)

**File:** `osx-ideTests/osx_ideTests.swift`
**Actions:**

- [x] Group related tests into separate test files
- [x] Create test categories: Core, Services, Components
- [ ] Add test documentation

---

### 4. ModernFileTreeView.init - Too Many Parameters

**File:** `osx-ide/Components/ModernFileTreeView.swift:127-146`
**Metrics:** 11 parameters (limit: 8)
**Status:** ✅ Completed
**Estimated Effort:** 0.5 day

**Actions:**

- [x] Create `FileTreeViewConfiguration` struct
- [x] Update initializer to accept configuration
- [x] Update all call sites
- [x] Write tests
- [x] Run tests and verify functionality

---

## 🟡 High Priority Issues (Priority 2)

### 5. High Complexity Methods (CCN 10-16)

**Status:** ⬜ Not Started
**Estimated Effort:** 2-3 days total

#### 5.1 QuickOpenOverlayView.fallbackFindFiles (CCN 16)

**File:** `osx-ide/Components/QuickOpenOverlayView.swift:120`
**Actions:**

- [ ] Extract file filtering logic
- [ ] Extract result limiting logic
- [ ] Extract error handling
- [ ] Write tests

#### 5.2 WorkspaceSearchService.fallbackSearch (CCN 16)

**File:** `osx-ide/Services/WorkspaceSearchService.swift:40`
**Actions:**

- [ ] Extract file enumeration logic
- [ ] Extract result matching logic
- [ ] Extract error handling
- [ ] Write tests

#### 5.3 ShellManager.start (74 LOC, CCN 11)

**File:** `osx-ide/Services/ShellManager.swift:43`
**Actions:**

- [ ] Extract PTY setup logic
- [ ] Extract process launch logic
- [ ] Extract error handling
- [ ] Write tests

#### 5.4 CodeEditorView.updateNSView (CCN 11)

**File:** `osx-ide/Components/CodeEditorView.swift:142`
**Actions:**

- [ ] Extract font update logic
- [ ] Extract word wrap logic
- [ ] Extract content update logic
- [ ] Write tests

#### 5.5 CodeEditorView.performAsyncHighlight (52 LOC, CCN 9)

**File:** `osx-ide/Components/CodeEditorView.swift:489`
**Actions:**

- [ ] Extract highlighting preparation logic
- [ ] Extract attribute application logic
- [ ] Write tests

#### 5.6 LineNumberRulerView.drawHashMarksAndLabels (56 LOC, CCN 9)

**File:** `osx-ide/Components/LineNumberRulerView.swift:42`
**Actions:**

- [ ] Extract line number calculation logic
- [ ] Extract drawing logic
- [ ] Write tests

#### 5.7 ModernFileTreeView.scheduleSearch (CCN 10)

**File:** `osx-ide/Components/ModernFileTreeCoordinator.swift`
**Actions:**

- [x] Extract search debouncing logic
- [x] Extract XCTest handling logic
- [x] Extract result processing logic
- [x] Write tests

#### 5.8 DatabaseManager.searchSymbolsWithPaths (52 LOC, CCN 9)

**File:** `osx-ide/Services/Index/Database/DatabaseManager.swift:340`
**Actions:**

- [ ] Extract SQL query building logic
- [ ] Extract parameter binding logic
- [ ] Write tests

#### 5.9 FileEditorStateManager.reloadFileFromDisk (CCN 11)

**File:** `osx-ide/Services/FileEditorStateManager.swift:505`
**Actions:**

- [ ] Extract file reading logic
- [ ] Extract conflict detection logic
- [ ] Extract UI update logic
- [ ] Write tests

#### 5.10 FileEditorStateManager.languageForFileExtension (CCN 10)

**File:** `osx-ide/Services/FileEditorStateManager.swift:555`
**Actions:**

- [ ] Extract extension mapping logic
- [ ] Extract fallback logic
- [ ] Write tests

---

### 6. Code Duplication - DRY Violations

**Status:** ✅ Completed
**Estimated Effort:** 0.5 day

#### 6.1 Duplicate Greeting Message

**File:** `osx-ide/Services/ChatHistoryManager.swift`
**Locations:** Lines 21, 32, 86
**Actions:**

- [x] Extract to `static let defaultGreeting` constant
- [x] Replace all occurrences
- [x] Write tests (`osx-ideTests/osx_ideTests.swift`)

#### 6.2 Repeated Error Handling Pattern

**File:** `osx-ide/Services/WorkspaceService.swift`
**Locations:** Lines 125, 158, 176, 193
**Actions:**

- [x] Create `mapToAppError(_ error: Error, operation: String)` helper
- [x] Replace all occurrences
- [x] Write tests (existing WorkspaceService tests remain green)

---

### 7. Concurrency Pattern Inconsistency

**Status:** ⬜ Not Started
**Estimated Effort:** 1 day

**Actions:**

- [ ] Audit all `DispatchQueue.main.async` usage
- [ ] Audit all `DispatchQueue.main.asyncAfter` usage
- [ ] Replace with `Task { @MainActor in ... }` where appropriate
- [ ] Replace asyncAfter with `Task.sleep` where appropriate
- [ ] Use `MainActor.assumeIsolated` for performance-critical paths
- [ ] Run tests and verify thread safety
- [ ] Update coding standards documentation

---

## 🟢 Medium Priority Issues (Priority 3)

### 8. Test Complexity

**Status:** ⬜ Not Started
**Estimated Effort:** 1-2 days

#### 8.1 SettingsGeneralUITests.testGeneralSettingsAffectEditor

**Metrics:** 74 LOC, CCN 12
**Actions:**

- [ ] Extract Given-When-Then helper methods
- [ ] Break into smaller test methods
- [ ] Add test documentation

#### 8.2 osx_ideUITests.testAppLaunchAndBasicUI

**Metrics:** CCN 9
**Actions:**

- [ ] Extract setup logic to helper method
- [ ] Extract assertion logic to helper method
- [ ] Add test documentation

#### 8.3 JSONHighlighterTests.testJSONHighlighting

**Metrics:** 60 LOC
**Actions:**

- [ ] Extract test data to constants
- [ ] Extract assertion logic to helper method
- [ ] Add test documentation

#### 8.4 MarkdownParserTests.testParse_withMultipleCodeBlocks_preservesOrder

**Metrics:** CCN 11
**Actions:**

- [ ] Extract test data setup to helper method
- [ ] Extract assertion logic to helper method
- [ ] Add test documentation

---

### 9. Missing Error Context

**Status:** ⬜ Not Started
**Estimated Effort:** 0.5 day

**Actions:**

- [ ] Audit all error conversion points
- [ ] Add operation context to error messages
- [ ] Write tests for error scenarios
- [ ] Update error handling documentation

---

### 10. Hard-coded Strings

**Status:** ⬜ Not Started
**Estimated Effort:** 1 day

**Actions:**

- [ ] Audit all user-facing strings
- [ ] Extract to Localizable.strings
- [ ] Update code to use localized strings
- [ ] Add missing translations
- [ ] Write tests for localization

---

## ⚪ Low Priority Issues (Priority 4)

### 11. Documentation

**Status:** ⬜ Not Started
**Estimated Effort:** 2-3 days

**Actions:**

- [ ] Add Swift documentation comments for public APIs
- [ ] Document complex private methods
- [ ] Document protocol contracts
- [ ] Create architecture documentation
- [ ] Update README with architecture overview

---

### 12. Performance Opportunities

**Status:** ⬜ Not Started
**Estimated Effort:** 1-2 days

#### 12.1 CodeEditorView.performAsyncHighlight

**Actions:**

- [ ] Implement incremental highlighting
- [ ] Add performance benchmarks
- [ ] Profile and optimize

#### 12.2 ModernFileTreeView.scheduleSearch

**Actions:**

- [ ] Make debounce delay configurable
- [ ] Add performance benchmarks
- [ ] Profile and optimize

---

## Progress Summary

### Overall Progress

- **Critical Issues:** 3/4 completed (75%)
- **High Priority:** 1/3 completed (33%)
- **Medium Priority:** 0/4 completed (0%)
- **Low Priority:** 0/2 completed (0%)
- **Total:** 4/13 completed (31%)

### Estimated Total Effort

- **Critical:** 8.5-11.5 days
- **High:** 3.5-4.5 days
- **Medium:** 4.5-5.5 days
- **Low:** 3-5 days
- **Total:** 19.5-26.5 days

---

## Notes

### Completed Items

- DRY fixes: `ChatHistoryManager` default greeting + `WorkspaceService` error mapping helper (with tests)
- Parameter reduction: `ModernCoordinator` now takes `Configuration` and tests/build pass (`./run.sh test`)
- Large file refactors: `CodeEditorView.swift` + `ModernFileTreeView.swift` have been split into smaller components (tests/build pass)
- Tests: `osx_ideTests.swift` has been split into focused test suites (tests/build pass)

### Blocked Items

None

### Decisions Made

None

### References

- [Project README](../README.md)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [SOLID Principles](../.windsurf/rules/project.md)
