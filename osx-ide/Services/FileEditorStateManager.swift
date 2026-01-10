//
//  FileEditorStateManager.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import Darwin

private final class FileChangeMonitor {
    private let url: URL
    private let eventMask: DispatchSource.FileSystemEvent
    private let queue: DispatchQueue
    private let handler: (DispatchSource.FileSystemEvent) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var isActive = false

    init(
        url: URL,
        eventMask: DispatchSource.FileSystemEvent = [.write, .extend, .attrib, .rename, .delete],
        queue: DispatchQueue = DispatchQueue(label: "FileChangeMonitor"),
        handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) {
        self.url = url
        self.eventMask = eventMask
        self.queue = queue
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: eventMask,
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.handler(source.data)
        }
        source.setCancelHandler { [weak self] in
            self?.closeDescriptor()
        }
        self.source = source
        isActive = true
        source.resume()
    }

    func stop() {
        guard isActive else {
            closeDescriptor()
            return
        }
        isActive = false
        source?.cancel()
        source = nil
    }

    private func closeDescriptor() {
        guard fileDescriptor >= 0 else { return }
        close(fileDescriptor)
        fileDescriptor = -1
    }
}

/// Manages file editor state and operations
@MainActor
final class EditorPaneStateManager: ObservableObject {
    struct EditorTab: Identifiable, Equatable {
        let id: UUID
        var filePath: String
        var language: String
        var content: String
        var isDirty: Bool
        var selectedRange: NSRange?

        init(filePath: String, language: String, content: String, isDirty: Bool, selectedRange: NSRange? = nil) {
            self.id = UUID()
            self.filePath = filePath
            self.language = language
            self.content = content
            self.isDirty = isDirty
            self.selectedRange = selectedRange
        }
    }

    func closeTab(filePath: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == filePath }) else { return }
        closeTab(id: tabs[idx].id)
    }

    func renameTab(oldPath: String, newPath: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == oldPath }) else { return }
        tabs[idx].filePath = newPath

        if activeTabID == tabs[idx].id {
            selectedFile = newPath
            fileEditorService.selectedFile = newPath
        }

        endWatchingFile(at: oldPath)
        beginWatchingFile(at: newPath)
    }

    @Published var tabs: [EditorTab] = []
    @Published var activeTabID: UUID? = nil
    @Published var selectedFile: String? = nil
    @Published var selectedRange: NSRange? = nil {
        didSet {
            if !isLoadingFile {
                updateActiveTabSelectionFromEditor()
            }
        }
    }
    @Published var editorContent: String = "" {
        didSet {
            if !isLoadingFile {
                detectLanguageForUntitledBufferIfNeeded(newContent: editorContent)
                isDirty = true
                updateActiveTabFromEditor()
            }
        }
    }
    @Published var editorLanguage: String = "swift"
    @Published var isDirty: Bool = false
    
    private var isLoadingFile = false
    private let fileEditorService: FileEditorServiceProtocol
    private let fileDialogService: FileDialogServiceProtocol
    private let fileSystemService: FileSystemService
    private var fileWatchers: [String: FileChangeMonitor] = [:]
    private var pendingReloads: [String: DispatchWorkItem] = [:]
    private var pendingWatchRestarts: [String: DispatchWorkItem] = [:]
    
    init(fileEditorService: FileEditorServiceProtocol, fileDialogService: FileDialogServiceProtocol, fileSystemService: FileSystemService) {
        self.fileEditorService = fileEditorService
        self.fileDialogService = fileDialogService
        self.fileSystemService = fileSystemService
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopWatchingAllFiles()
        }
    }

    private func detectLanguageForUntitledBufferIfNeeded(newContent: String) {
        guard selectedFile == nil else { return }
        guard editorLanguage == "swift" || editorLanguage == "text" else { return }

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.first == "{" || trimmed.first == "[" else { return }

        guard let data = trimmed.data(using: .utf8) else { return }
        guard (try? JSONSerialization.jsonObject(with: data, options: [])) != nil else { return }

        editorLanguage = "json"
    }
    
    // MARK: - File Operations
    
    /// Load file content into editor with validation
    func loadFile(from url: URL) {
        // Input validation
        guard validateFilePath(url.path) else {
            fileEditorService.handleError(AppError.invalidFilePath("Invalid file path: \(url.path)"))
            return
        }
        
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            return // Directory loading handled by WorkspaceStateManager
        }
        
        openTab(for: url)
    }
    
    /// Save current content to selected file
    func saveFile() {
        guard selectedFile != nil else {
            Task { @MainActor in
                await self.saveFileAs()
            }
            return
        }
        syncServiceState()
        fileEditorService.saveFile()
        isDirty = false
        persistActiveEditorStateToTab()
        if let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) {
            tabs[idx].isDirty = false
        }
    }
    
    /// Save file to new location
    func saveFileAs() async {
        syncServiceState()
        let defaultName: String
        if let selectedFile {
            defaultName = URL(fileURLWithPath: selectedFile).lastPathComponent
        } else {
            defaultName = "Untitled.swift"
        }
        guard let url = await fileDialogService.saveFile(defaultFileName: defaultName, allowedContentTypes: [.swiftSource, .plainText]) else {
            return
        }
        fileEditorService.saveFileAs(to: url)
        selectedFile = fileEditorService.selectedFile
        editorLanguage = fileEditorService.editorLanguage
        isDirty = false
    }
    
    /// Create new empty file with validation
    func newFile() {
        stopWatchingAllFiles()
        tabs.removeAll()
        activeTabID = nil
        selectedRange = nil
        // Reset editor state
        fileEditorService.newFile()
        selectedFile = nil
        editorContent = ""
        isDirty = false
        editorLanguage = "swift"
    }

    func activateTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        persistActiveEditorStateToTab()
        activeTabID = id

        let tab = tabs[idx]
        beginWatchingFile(at: tab.filePath)
        isLoadingFile = true
        defer { isLoadingFile = false }
        selectedFile = tab.filePath
        editorLanguage = tab.language
        editorContent = tab.content
        isDirty = tab.isDirty
        selectedRange = tab.selectedRange
    }

    func activateTab(filePath: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == filePath }) else { return }
        activateTab(id: tabs[idx].id)
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs.remove(at: idx)
        endWatchingFile(at: removed.filePath)

        if activeTabID == removed.id {
            if let newActive = tabs.last {
                activateTab(id: newActive.id)
            } else {
                newFile()
            }
        }
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    func closeOtherTabs(keeping id: UUID) {
        guard let keepIdx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let keep = tabs[keepIdx]
        let removedPaths = tabs.filter { $0.id != id }.map { $0.filePath }
        for path in removedPaths {
            endWatchingFile(at: path)
        }
        tabs = [keep]
        activateTab(id: keep.id)
    }

    func activateNextTab() {
        guard !tabs.isEmpty else { return }
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else {
            activateTab(id: tabs[0].id)
            return
        }
        let nextIdx = (idx + 1) % tabs.count
        activateTab(id: tabs[nextIdx].id)
    }

    func activatePreviousTab() {
        guard !tabs.isEmpty else { return }
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else {
            activateTab(id: tabs[0].id)
            return
        }
        let prevIdx = (idx - 1 + tabs.count) % tabs.count
        activateTab(id: tabs[prevIdx].id)
    }

    private func openTab(for url: URL) {
        let path = url.path

        if let existingIdx = tabs.firstIndex(where: { $0.filePath == path }) {
            activateTab(id: tabs[existingIdx].id)
            return
        }

        persistActiveEditorStateToTab()

        isLoadingFile = true
        defer { isLoadingFile = false }

        fileEditorService.loadFile(from: url)

        let selectedPath = fileEditorService.selectedFile
        let content = fileEditorService.editorContent
        let language = fileEditorService.editorLanguage

        guard let selectedPath else { return }

        let newTab = EditorTab(filePath: selectedPath, language: language, content: content, isDirty: false)
        tabs.append(newTab)
        activeTabID = newTab.id
        beginWatchingFile(at: selectedPath)

        selectedFile = selectedPath
        editorContent = content
        editorLanguage = language
        isDirty = false
        selectedRange = nil
    }

    private func persistActiveEditorStateToTab() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].content = editorContent
        tabs[idx].language = editorLanguage
        tabs[idx].isDirty = isDirty
        tabs[idx].selectedRange = selectedRange
    }

    private func updateActiveTabFromEditor() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].content = editorContent
        tabs[idx].language = editorLanguage
        tabs[idx].isDirty = true
    }

    private func updateActiveTabSelectionFromEditor() {
        guard let activeID = activeTabID, let idx = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        tabs[idx].selectedRange = selectedRange
    }
    
    /// Validate file path for security and correctness
    private func validateFilePath(_ path: String) -> Bool {
        // Check for empty or whitespace-only paths
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        // Check for path traversal attempts
        if path.contains("..") || path.contains("/../") {
            return false
        }
        
        // Check for invalid characters (basic validation)
        let invalidChars = CharacterSet(charactersIn: "<>:\"?*\n\r")
        guard path.rangeOfCharacter(from: invalidChars) == nil else {
            return false
        }
        
        // Check path length
        if path.count > AppConstants.FileSystem.maxPathLength {
            return false
        }
        
        return true
    }
    
    // MARK: - Content Management
    
    func updateEditorContent(_ newContent: String) {
        editorContent = newContent
        fileEditorService.editorContent = newContent
    }
    
    func setEditorLanguage(_ language: String) {
        editorLanguage = language
        fileEditorService.editorLanguage = language
    }

    func selectLine(_ line: Int) {
        let target = max(1, line)
        let ns = editorContent as NSString
        let lines = ns.components(separatedBy: "\n")
        if lines.isEmpty {
            selectedRange = NSRange(location: 0, length: 0)
            return
        }

        var currentLine = 1
        var location = 0
        for idx in 0..<lines.count {
            if currentLine == target {
                break
            }
            location += (lines[idx] as NSString).length
            location += 1
            currentLine += 1
        }

        location = max(0, min(location, ns.length))
        selectedRange = NSRange(location: location, length: 0)
    }

    // MARK: - File Watching

    private func beginWatchingFile(at path: String) {
        guard fileWatchers[path] == nil else { return }
        let url = URL(fileURLWithPath: path)
        let watcher = FileChangeMonitor(
            url: url,
            queue: DispatchQueue(label: "FileChangeMonitor.\(url.lastPathComponent)")
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFileSystemEvent(event, forPath: path)
            }
        }
        fileWatchers[path] = watcher
        watcher.start()
    }

    private func endWatchingFile(at path: String) {
        pendingReloads[path]?.cancel()
        pendingReloads.removeValue(forKey: path)

        pendingWatchRestarts[path]?.cancel()
        pendingWatchRestarts.removeValue(forKey: path)

        if let watcher = fileWatchers[path] {
            watcher.stop()
            fileWatchers.removeValue(forKey: path)
        }
    }

    private func stopWatchingAllFiles(except keepPath: String? = nil) {
        let paths = fileWatchers.keys.filter { $0 != keepPath }
        for path in paths {
            endWatchingFile(at: path)
        }
    }

    private func handleFileSystemEvent(_ event: DispatchSource.FileSystemEvent, forPath path: String) {
        if event.contains(.rename) || event.contains(.delete) || event.contains(.revoke) {
            endWatchingFile(at: path)
            scheduleWatchRestart(for: path)
            return
        }

        if event.contains(.write) || event.contains(.extend) || event.contains(.attrib) {
            scheduleReload(for: path)
        }
    }

    private func scheduleWatchRestart(for path: String, attempt: Int = 0) {
        let maxAttempts = 5
        guard attempt < maxAttempts else { return }

        pendingWatchRestarts[path]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: path) {
                self.beginWatchingFile(at: path)
                self.scheduleReload(for: path)
            } else {
                self.scheduleWatchRestart(for: path, attempt: attempt + 1)
            }
        }
        pendingWatchRestarts[path] = work
        let delay = 0.2 * Double(attempt + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleReload(for path: String) {
        pendingReloads[path]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadFileFromDisk(for: path)
        }
        pendingReloads[path] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func reloadFileFromDisk(for path: String) {
        guard let idx = tabs.firstIndex(where: { $0.filePath == path }) else { return }
        guard !tabs[idx].isDirty else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }

        let url = URL(fileURLWithPath: path)
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard !isDirectory else { return }

        switch fileSystemService.readFileResult(at: url) {
        case .success(let content):
            guard content != tabs[idx].content else { return }
            tabs[idx].content = content
            tabs[idx].isDirty = false

            if activeTabID == tabs[idx].id {
                isLoadingFile = true
                defer { isLoadingFile = false }
                editorContent = content
                isDirty = false
            }
        case .failure:
            return
        }
    }

    private func syncServiceState() {
        fileEditorService.selectedFile = selectedFile
        fileEditorService.editorContent = editorContent
        fileEditorService.editorLanguage = editorLanguage
    }
    
    // MARK: - Computed Properties
    
    /// Check if file can be saved
    var canSave: Bool {
        return isDirty && selectedFile != nil
    }
    
    /// Get current file name for display
    var displayName: String {
        if let selectedFile {
            return URL(fileURLWithPath: selectedFile).lastPathComponent
        }
        return "Untitled"
    }
    
    // MARK: - Language Detection
    
    /// Returns the language identifier for a given file extension
    static func languageForFileExtension(_ fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "swift": return "swift"
        case "js": return "javascript"
        case "jsx": return "jsx"
        case "ts": return "typescript"
        case "tsx": return "tsx"
        case "py": return "python"
        case "html": return "html"
        case "css": return "css"
        case "json": return "json"
        default: return "text"
        }
    }
}

@MainActor
final class FileEditorStateManager: ObservableObject {
    enum PaneID: String, Codable, Sendable {
        case primary
        case secondary
    }

    enum SplitAxis: String, Codable, Sendable {
        case vertical
        case horizontal
    }

    @Published var isSplitEditor: Bool = false
    @Published var splitAxis: SplitAxis = .vertical
    @Published var focusedPane: PaneID = .primary

    let primaryPane: EditorPaneStateManager
    let secondaryPane: EditorPaneStateManager

    init(fileEditorService: FileEditorServiceProtocol, fileDialogService: FileDialogServiceProtocol, fileSystemService: FileSystemService) {
        self.primaryPane = EditorPaneStateManager(
            fileEditorService: fileEditorService,
            fileDialogService: fileDialogService,
            fileSystemService: fileSystemService
        )
        self.secondaryPane = EditorPaneStateManager(
            fileEditorService: fileEditorService,
            fileDialogService: fileDialogService,
            fileSystemService: fileSystemService
        )

        primaryPane.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        secondaryPane.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    var focusedPaneState: EditorPaneStateManager {
        focusedPane == .primary ? primaryPane : secondaryPane
    }

    func focus(_ pane: PaneID) {
        focusedPane = pane
    }

    func toggleSplit(axis: SplitAxis) {
        if isSplitEditor, splitAxis == axis {
            isSplitEditor = false
            focusedPane = .primary
            return
        }

        splitAxis = axis
        isSplitEditor = true
        if focusedPane == .secondary {
            focusedPane = .secondary
        }
    }

    func closeSplit() {
        isSplitEditor = false
        focusedPane = .primary
    }

    func focusNextPane() {
        guard isSplitEditor else { return }
        focusedPane = (focusedPane == .primary) ? .secondary : .primary
    }

    func openInOtherPane(from url: URL) {
        if !isSplitEditor {
            isSplitEditor = true
        }
        let other: PaneID = (focusedPane == .primary) ? .secondary : .primary
        focusedPane = other
        focusedPaneState.loadFile(from: url)
    }

    func loadFile(from url: URL) {
        focusedPaneState.loadFile(from: url)
    }

    func activateTab(id: UUID) {
        focusedPaneState.activateTab(id: id)
    }

    func activateTab(filePath: String) {
        if primaryPane.tabs.contains(where: { $0.filePath == filePath }) {
            focusedPane = .primary
            primaryPane.activateTab(filePath: filePath)
            return
        }

        if secondaryPane.tabs.contains(where: { $0.filePath == filePath }) {
            focusedPane = .secondary
            secondaryPane.activateTab(filePath: filePath)
        }
    }

    func saveFile() {
        focusedPaneState.saveFile()
    }

    func saveFileAs() async {
        await focusedPaneState.saveFileAs()
    }

    func selectLine(_ line: Int) {
        focusedPaneState.selectLine(line)
    }

    func closeActiveTab() {
        focusedPaneState.closeActiveTab()
    }

    func activateNextTab() {
        focusedPaneState.activateNextTab()
    }

    func activatePreviousTab() {
        focusedPaneState.activatePreviousTab()
    }

    func newFile() {
        primaryPane.newFile()
        secondaryPane.newFile()
        closeSplit()
    }

    func closeAllTabs() {
        primaryPane.newFile()
        secondaryPane.newFile()
    }

    func closeTab(filePath: String) {
        if primaryPane.tabs.contains(where: { $0.filePath == filePath }) {
            primaryPane.closeTab(filePath: filePath)
        }
        if secondaryPane.tabs.contains(where: { $0.filePath == filePath }) {
            secondaryPane.closeTab(filePath: filePath)
        }
    }

    func renameTab(oldPath: String, newPath: String) {
        if primaryPane.tabs.contains(where: { $0.filePath == oldPath }) {
            primaryPane.renameTab(oldPath: oldPath, newPath: newPath)
        }
        if secondaryPane.tabs.contains(where: { $0.filePath == oldPath }) {
            secondaryPane.renameTab(oldPath: oldPath, newPath: newPath)
        }
    }

    func tab(for filePath: String) -> EditorPaneStateManager.EditorTab? {
        if let tab = primaryPane.tabs.first(where: { $0.filePath == filePath }) {
            return tab
        }
        if let tab = secondaryPane.tabs.first(where: { $0.filePath == filePath }) {
            return tab
        }
        return nil
    }

    func isFileOpenAndDirty(filePath: String) -> Bool {
        tab(for: filePath)?.isDirty ?? false
    }

    var tabs: [EditorPaneStateManager.EditorTab] {
        focusedPaneState.tabs
    }

    var activeTabID: UUID? {
        focusedPaneState.activeTabID
    }

    var selectedFile: String? {
        focusedPaneState.selectedFile
    }

    var editorContent: String {
        get { focusedPaneState.editorContent }
        set { focusedPaneState.editorContent = newValue }
    }

    var editorLanguage: String {
        get { focusedPaneState.editorLanguage }
        set { focusedPaneState.editorLanguage = newValue }
    }

    var isDirty: Bool {
        focusedPaneState.isDirty
    }

    var canSave: Bool {
        focusedPaneState.canSave
    }

    var displayName: String {
        focusedPaneState.displayName
    }

    var selectedRange: NSRange? {
        get { focusedPaneState.selectedRange }
        set { focusedPaneState.selectedRange = newValue }
    }

    static func languageForFileExtension(_ fileExtension: String) -> String {
        EditorPaneStateManager.languageForFileExtension(fileExtension)
    }
}
