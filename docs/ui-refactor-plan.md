# macOS 26 UI Refactoring Plan

## Goal
Replace all custom UI components with macOS 26 native SwiftUI APIs in one complete sweep. No backward compatibility. Target: `.glassBackgroundEffect()`, `.toolbar {}`, `.searchable()`, `NavigationSplitView`, `Form`, native `List`, SwiftUI ShapeStyles.

## Strategy

### Layered approach — build from foundation up
```
Phase 0: ShapeStyles & Typography  ──┐
                                     ├──▶ Phase 3: Settings (Form)
Phase 1: Layout & Navigation  ──────┤         |
                                     │         ├──▶ Phase 4: Lists & Overlays
Phase 2: Toolbar & Search  ─────────┘         |
                                              └──▶ Phase 5: Materials & Glass
```

Each phase must compile and pass tests before the next starts. No regressions.

---

## Phase 0: ShapeStyles & Typography

**Scope**: Bulk text/color cleanup across ALL 60+ view files.

### Replacements

| Pattern | Replacement | Files affected |
|---------|-------------|----------------|
| `.foregroundColor(.primary)` | `.foregroundStyle(.primary)` | ~80 files |
| `.foregroundColor(.secondary)` | `.foregroundStyle(.secondary)` | ~80 files |
| `.foregroundColor(.accentColor)` | `.foregroundStyle(.tint)` | ~15 files |
| `.foregroundColor(.red/green/blue/etc)` | `.foregroundStyle(.red/.green/.blue)` | ~20 files |
| `Color(NSColor.windowBackgroundColor)` | `.background(.windowBackground)` | 10 files |
| `Color(NSColor.separatorColor)` | `.stroke(.separator)` or `.foregroundStyle(.separator)` | 8 files |
| `Color(NSColor.controlBackgroundColor)` | `.background(.regularMaterial)` or `.background(.controlBackground)` | 20+ files |
| `Color(NSColor.textBackgroundColor)` | `.background(.textBackground)` | 5 files |
| `.font(.system(size: 11, weight: .medium))` | `.font(.caption.weight(.medium))` | ~100 instances |
| `.font(.system(size: 10, weight: .semibold))` | `.font(.caption2.weight(.semibold))` | ~50 instances |
| `.font(.system(size: 12))` | `.font(.body)` | ~30 instances |
| `.font(.system(size: 9))` | `.font(.caption2)` | ~20 instances |
| `Color(NSColor.controlAccentColor)` | `.tint` (automatic) | 2 files |
| `Color.white.opacity(x)` strokes | `.stroke(.separator.opacity(x))` | 5 files |
| `Color.gray.opacity(x)` backgrounds | `.background(.windowBackground)` or `.background(.regularMaterial.opacity(x))` | 15 files |

### Automation strategy
Bulk regex find-replace in text editor, then manual review per file.

### Verification
- Build succeeds with zero warnings
- Run `./run.sh build` — all targets compile
- Visual scan: every `.foregroundStyle()` and `.font()` is semantic, no remaining `.foregroundColor()` in SwiftUI view code
- `grep -r "foregroundColor\|\.font(\.system(size:" osx-ide/Components/ --include="*.swift"` returns 0 hits

---

## Phase 1: Layout & Navigation

**Scope**: ContentView.swift, LayoutView.swift, WindowAccessor, PanelCoordinator, sidebar

### 1a. Replace custom layout with NavigationSplitView

**ContentView.swift**: Replace the entire `HStack(spacing: 0)` workspace layout with:

```swift
NavigationSplitView(
    columnVisibility: $columnVisibility,
    sidebar: { SidebarView(context: context) },
    content: { EditorView(context: context) },
    detail: { DetailPanel(context: context) }
)
.navigationSplitViewStyle(.balanced)
```

- `SidebarView` = FileExplorerView (sidebar column, 200-300pt)
- `EditorView` = EditorPaneView (content column)
- `DetailPanel` = AIChatPanel (detail column, 240-480pt)

**LayoutView.swift**: Remove — `NavigationSplitView` handles splitter natively. Remove `HSplitView` AppKit bridge, `ResizeCursorView`, `CursorRectNSView`.

**PanelCoordinator.swift**: Remove — width constraints handled by `.navigationSplitViewColumnWidth(min:ideal:max:)`.

### 1b. Replace WindowAccessor with native modifiers

**WindowSetupView / WindowAccessor**: Remove entirely. Configure window with:

```swift
Window("osx-ide", id: "main") {
    ContentView(...)
}
.windowStyle(.titleBarAndToolbar)
.windowToolbarStyle(.unified)  // not .unifiedCompact for Liquid Glass
.windowResizability(.automatic)
.defaultWindowPlacement(.center)
```

### 1c. Replace sidebar NSOutlineView with native OutlineGroup

**ModernFileTreeView.swift, FileTreeAppearanceCoordinator.swift, FileTreeSearchCoordinator.swift, ModernFileTreeCoordinator.swift**: Remove all 4 files. Replace with:

```swift
List(children: \.children) { node in
    Label(node.name, systemImage: node.icon)
}
.listStyle(.sidebar)
.searchable(text: $searchQuery)
```

### Files to delete
- `WindowAccessor.swift`
- `FocusForwardingContainerView.swift`
- `CursorRectNSView.swift`
- `ResizeCursorView.swift`
- `LayoutView.swift`
- `ModernFileTreeView.swift`
- `FileTreeAppearanceCoordinator.swift`
- `FileTreeSearchCoordinator.swift`
- `ModernFileTreeCoordinator.swift`
- `LineNumberRulerView.swift` (in code editor — is this needed?)
- `PanelCoordinator.swift`

### Verification
- Build succeeds
- `./run.sh build` passes
- App launches with proper sidebar/content/detail layout
- Sidebar resizes natively
- Window can be resized, maximized, restored
- File tree shows files with expand/collapse
- Search filters the tree
- Chat panel resizes

---

## Phase 2: Toolbar & Search

**Scope**: AIChatPanel, EditorPaneView, ContentView bottom panel, all search bars

### 2a. Chat panel toolbar

**AIChatPanel.swift**: Replace custom HStack tab bar + mode selector with:

```swift
.toolbar {
    ToolbarItemGroup(placement: .primaryAction) {
        // provider/reasoning menu
    }
    ToolbarItem(placement: .secondaryAction) {
        // new conversation button
    }
}
```

Use `.toolbarBackground(.visible)` for material toolbar.

### 2b. Editor pane toolbar

**EditorPaneView.swift**: Replace custom HStack tab bar with:

```swift
.toolbar {
    ToolbarItemGroup(placement: .automatic) {
        ForEach(openFiles) { file in
            Text(file.name)
        }
    }
}
```

### 2c. Bottom panel toolbar

**ContentView.swift bottomPanelHeader**: Replace with:

```swift
.toolbar(removing: .sidebarToggle) {  // if sidebar already handled by NavigationSplitView
    ToolbarItem(placement: .bottomBar) {
        Picker("Panel", selection: $selectedPanel) { ... }
    }
}
```

### 2d. Search bars — all 6 → `.searchable()`

| File | Current pattern | Replacement |
|------|----------------|-------------|
| FileExplorerView | `TextField + magnifyingglass` | `.searchable(text: $searchQuery)` on parent |
| LanguageModulesTab | `TextField + magnifyingglass` | `.searchable(text: $searchText)` on ScrollView |
| GlobalSearchOverlayView | Custom TextField in overlayScaffold | Convert to `.sheet()` with `.searchable()` |
| QuickOpenOverlayView | Custom TextField in overlayScaffold | Convert to `.sheet()` with `.searchable()` + `.searchSuggestions {}` |
| GoToSymbolOverlayView | Custom TextField | Convert to `.sheet()` with `.searchable()` |
| CommandPaletteOverlayView | Custom TextField | Convert to `.sheet()` with `.searchable()` |

### Verification
- Toolbar shows native macOS segmented controls and buttons
- No custom HStack tab bars exist
- All search bars use `.searchable()` — `grep "searchable"` returns 6+ hits
- Search debounces natively
- Search suggestions work for quick open

---

## Phase 3: Settings

**Scope**: SettingsView, all 5 SettingsTabs, SettingsComponents, SettingsRow, SettingsStatusPill, OverlayCard

### 3a. Replace SettingsView

**SettingsView.swift**: Replace `ZStack + TabView` with:

```swift
NavigationSplitView {
    List(selection: $selectedTab) {
        Label("General", systemImage: "gearshape")
        Label("AI", systemImage: "sparkles")
        Label("Agent", systemImage: "bolt.fill")
        Label("Modules", systemImage: "puzzlepiece")
    }
    .listStyle(.sidebar)
} detail: {
    Form {
        Section {
            // content
        } header: {
            Label("General", systemImage: "gearshape")
        }
    }
    .formStyle(.grouped)
}
```

### 3b. Convert each tab to Form

Each `SettingsTab` → a `Form` with `Section` groups:

```swift
Form {
    Section {
        Toggle("Dark Mode", isOn: $darkMode)
        Slider(value: $fontSize, in: 10...24) {
            Text("Font Size")
        }
    } header: {
        Text("Appearance")
    }
    
    Section {
        Button("Reset", role: .destructive) { ... }
    }
}
.formStyle(.grouped)
```

- **GeneralSettingsTab**: Form with Sections for Appearance, Behavior, Reset
- **AISettingsTab**: Form with Sections for API Keys, Provider Selection, Local Models
- **AgentSettingsTab**: Form with Sections for Behavior, Limits
- **LanguageModulesTab**: Form with `.searchable()` + Section per language
- **LocalModelSettingsView**: Form with Section per model
- **EmbeddingModelSettingsView**: Form with Section per model

### 3c. Remove custom SettingsComponents

Delete or gut:
- `SettingsComponents.swift` — `SettingsCard`, `SettingsRow` no longer needed
- `SettingsStatusPill.swift` — use native `Label` with `systemImage`
- `OverlayCard.swift`, `OverlayScaffold.swift` — replaced by native `.sheet()`

### Verification
- Settings opens as native macOS settings panel (sidebar + grouped form)
- Every control (Toggle, Slider, Picker, Button) has native macOS appearance
- No custom `SettingsCard` backgrounds or strokes
- Search in LanguageModules tab works natively

---

## Phase 4: Lists & Overlays

**Scope**: MessageListView, LogsPanelView, ActivityFeedView, OverlayContainer, all overlays

### 4a. Replace ScrollView+LazyVStack with native List

**MessageListView.swift**: Convert the inner chat list:

```swift
List(visibleMessages) { message in
    MessageView(message: ..., ...)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
}
.listStyle(.plain)
```

- Loses manual `scrollToBottom` — use `.defaultScrollAnchor(.bottom)` instead (macOS 14+)
- Loses custom transitions — use `.transition(.opacity)` on rows

**LogsPanelView.swift**: Same pattern — native `List` with `.listStyle(.plain)` and monospaced font on rows.

**ActivityFeedView.swift**: Replace custom `VStack` + `ForEach` with `List` or `DisclosureGroup`.

### 4b. Replace OverlayContainer with native sheets

**OverlayHostView / OverlayContainer**: Replace custom ZStack overlay system:

```swift
.sheet(isPresented: $showQuickOpen) {
    QuickOpenView(...)
}
.sheet(isPresented: $showGlobalSearch) {
    GlobalSearchView(...)
}
.popover(isPresented: $showCommandPalette) {
    CommandPaletteView(...)
}
```

Each overlay view gets its own `.sheet()` or `.popover()` modifier on the appropriate parent view. Remove `OverlayContainer.swift`, `OverlayCard.swift`, `OverlayScaffold.swift`.

### 4c. NewProjectDialog

**NewProjectDialog.swift**: Replace custom VStack with:

```swift
.sheet(isPresented: $isPresented) {
    Form {
        TextField("Name", text: $name)
        TextField("Path", text: $path)
        HStack {
            Button("Cancel") { dismiss() }
            Button("Create") { ... }
                .buttonStyle(.borderedProminent)
        }
    }
    .formStyle(.grouped)
    .frame(idealWidth: 400, idealHeight: 250)
}
```

### Verification
- Message list renders in native `List` with proper separators
- `defaultScrollAnchor(.bottom)` keeps chat scrolled to bottom
- All overlays use `.sheet()` or `.popover()` — `grep "OverlayContainer\|overlayScaffold"` returns 0
- Quick Open, Global Search, Command Palette all use native sheet presentation
- Keyboard dismissal (Escape) works on all overlays

---

## Phase 5: Materials & Glass

**Scope**: GlassStyle.swift, all `.nativeGlassBackground()` calls

### 5a. Replace nativeGlassBackground

**GlassStyle.swift**: Remove `nativeGlassBackground()` and `liquidGlassCard()`. Replace all call sites with:

```swift
.glassBackgroundEffect()  // macOS 26 native Liquid Glass API
```

For views that need specific corner radii:

```swift
.glassBackgroundEffect()
.clipShape(.rect(cornerRadius: 12, style: .continuous))
```

### 5b. Audit all material usage

Replace any remaining `Color(NSColor.*)` backgrounds:

- `Color(NSColor.windowBackgroundColor)` → `.background(.windowBackground)`
- `Color(NSColor.controlBackgroundColor)` → `.background(.regularMaterial)`
- Custom blur overlays → remove (`.glassBackgroundEffect()` handles blur)

### 5c. SettingsStatusPill

Replace with native `Label` and `.badge()` modifier.

### Verification
- `grep "nativeGlassBackground\|liquidGlassCard\|NSColor\."` returns 0 in Components/
- Every background uses SwiftUI ShapeStyle or `.glassBackgroundEffect()`
- No custom `Rectangle().blur()` overlays
- Visual: consistent glass appearance across all cards, popovers, and sheets

---

## Milestone Tracker

```
Phase 0: ShapeStyles & Typography
  [ ] All .foregroundColor() → .foregroundStyle()
  [ ] All .font(.system(size:)) → semantic fonts
  [ ] All Color(NSColor.*) → SwiftUI ShapeStyles
  [ ] Build passes, zero warnings
  [ ] grep returns 0 hits for deprecated patterns

Phase 1: Layout & Navigation
  [ ] ContentView uses NavigationSplitView
  [ ] WindowAccessor removed, native modifiers used
  [ ] NSOutlineView sidebar replaced with List(children:)
  [ ] LayoutView, PanelCoordinator removed
  [ ] Build passes, app launches in proper split-view layout

Phase 2: Toolbar & Search
  [ ] AIChatPanel uses .toolbar {}, no custom tab bar
  [ ] EditorPaneView uses .toolbar {}, no custom tab bar
  [ ] All 6 search bars use .searchable()
  [ ] ContentView bottom panel uses .toolbar(placement: .bottomBar)
  [ ] Build passes, toolbars render natively

Phase 3: Settings
  [ ] SettingsView uses NavigationSplitView + Form
  [ ] All tabs are Form with Section groups
  [ ] SettingsCard, SettingsRow, SettingsStatusPill removed
  [ ] Build passes, settings render as native grouped form

Phase 4: Lists & Overlays
  [ ] MessageListView uses native List
  [ ] LogsPanelView uses native List
  [ ] All overlays use .sheet()/.popover()
  [ ] OverlayContainer, OverlayCard, OverlayScaffold removed
  [ ] Build passes, lists render natively

Phase 5: Materials & Glass
  [ ] All .nativeGlassBackground() → .glassBackgroundEffect()
  [ ] No remaining Color(NSColor.*) in Components/
  [ ] GlassStyle.swift removed or gutted
  [ ] Build passes, consistent glass appearance
```

## File Deletion List

After all phases, these files should be deleted:

```
osx-ide/Components/LayoutView.swift
osx-ide/Components/WindowAccessor.swift
osx-ide/Components/FocusForwardingContainerView.swift
osx-ide/Components/CursorRectNSView.swift
osx-ide/Components/ResizeCursorView.swift
osx-ide/Components/ModernFileTreeView.swift
osx-ide/Components/FileTreeAppearanceCoordinator.swift
osx-ide/Components/FileTreeSearchCoordinator.swift
osx-ide/Components/ModernFileTreeCoordinator.swift
osx-ide/Components/FileTreeDialogCoordinator.swift
osx-ide/Components/PanelCoordinator.swift
osx-ide/Components/SettingsComponents.swift
osx-ide/Components/SettingsRow.swift
osx-ide/Components/SettingsStatusPill.swift
osx-ide/Components/OverlayContainer.swift
osx-ide/Components/OverlayCard.swift
osx-ide/Components/OverlayScaffold.swift
osx-ide/Components/OverlayScaffoldConfiguration.swift
osx-ide/Components/OverlayHeaderView.swift
osx-ide/Components/OverlayCommon.swift
osx-ide/Components/OverlayUtilities.swift
osx-ide/Components/OverlayLocalizer.swift
osx-ide/Components/OverlaySearchDebouncer.swift
osx-ide/Components/GlassStyle.swift
osx-ide/Components/NavigationLocationsOverlayView.swift
osx-ide/Components/RenameSymbolOverlayView.swift
```

## Testing Strategy

After each phase:
1. `./run.sh build` — must pass with zero errors
2. `./run.sh test` — run all existing tests, fix any that break due to renamed/removed types
3. Visual smoke test: launch app, verify the changed components render correctly
4. `grep` check: verify old patterns are fully removed (e.g., `foregroundColor` after Phase 0)

## Tracked in repo as
- `REFOCUS_TRACKER.md` — update with these phases
- New file: `UI_REFACTOR_SPEC.md` — this document
