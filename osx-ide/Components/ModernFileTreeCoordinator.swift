import SwiftUI
import AppKit

/// Modern coordinator for the file tree focusing on UI events and state bridging
@MainActor
final class ModernCoordinator: NSObject, NSOutlineViewDelegate, NSMenuDelegate {
    let dataSource = FileTreeDataSource()

    struct Configuration {
        let expandedRelativePaths: Binding<Set<String>>
        let selectedRelativePath: Binding<String?>
        let onOpenFile: (URL) -> Void
        let onCreateFile: (URL, String) -> Void
        let onCreateFolder: (URL, String) -> Void
        let onDeleteItem: (URL) -> Void
        let onRenameItem: (URL, String) -> Void
        let onRevealInFinder: (URL) -> Void
    }

    private let expandedRelativePaths: Binding<Set<String>>
    private let selectedRelativePath: Binding<String?>
    private let onOpenFile: (URL) -> Void
    private let onCreateFile: (URL, String) -> Void
    private let onCreateFolder: (URL, String) -> Void
    private let onDeleteItem: (URL) -> Void
    private let onRenameItem: (URL, String) -> Void
    private let onRevealInFinder: (URL) -> Void
    private weak var outlineView: NSOutlineView?
    private var searchWorkItem: DispatchWorkItem?
    private var searchGeneration: Int = 0
    var refreshToken: Int = 0
    private var lastRootPath: String?
    private var lastRootURL: URL?
    private var lastSearchQuery: String = ""
    private var lastShowHiddenFiles: Bool = false
    private var fontSize: Double = 13
    private var fontFamily: String = AppConstants.Editor.defaultFontFamily

    init(configuration: Configuration) {
        self.expandedRelativePaths = configuration.expandedRelativePaths
        self.selectedRelativePath = configuration.selectedRelativePath
        self.onOpenFile = configuration.onOpenFile
        self.onCreateFile = configuration.onCreateFile
        self.onCreateFolder = configuration.onCreateFolder
        self.onDeleteItem = configuration.onDeleteItem
        self.onRenameItem = configuration.onRenameItem
        self.onRevealInFinder = configuration.onRevealInFinder
        super.init()
    }

    func attach(outlineView: NSOutlineView) {
        self.outlineView = outlineView
        dataSource.outlineView = outlineView

        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu
    }

    private func clickedFileTreeItem() -> FileTreeItem? {
        guard let outlineView else { return nil }
        let row = outlineView.clickedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeItem
    }

    private func promptForRename(initialName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Rename"
        alert.informativeText = "Enter a new name."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: initialName)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func promptForNewItem(title: String, informativeText: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: "")
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func directoryForCreate() -> URL? {
        if let item = clickedFileTreeItem() {
            if dataSource.isDirectory(item.url) {
                return (item.url as URL).standardizedFileURL
            }
            return (item.url as URL).deletingLastPathComponent().standardizedFileURL
        }

        return lastRootURL?.standardizedFileURL
    }

    func update(rootURL: URL, searchQuery: String, showHiddenFiles: Bool, refreshToken: Int, fontSize: Double, fontFamily: String) {
        var needsReload = false

        if self.fontSize != fontSize || self.fontFamily != fontFamily {
            self.fontSize = fontSize
            self.fontFamily = fontFamily
            needsReload = true
        }

        if self.refreshToken != refreshToken {
            self.refreshToken = refreshToken
            dataSource.resetCaches()
            needsReload = true
        }

        let rootPath = rootURL.standardizedFileURL.path
        if lastRootPath != rootPath {
            lastRootPath = rootPath
            lastRootURL = rootURL.standardizedFileURL
            dataSource.setRootURL(rootURL)
            needsReload = true
        }

        if lastSearchQuery != searchQuery {
            lastSearchQuery = searchQuery
            setSearchQuery(searchQuery)
            needsReload = true
        }

        if lastShowHiddenFiles != showHiddenFiles {
            lastShowHiddenFiles = showHiddenFiles
            dataSource.setShowHiddenFiles(showHiddenFiles)
            needsReload = true
        }

        if needsReload {
            // Avoid triggering delegate callbacks that publish SwiftUI state during view updates.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.outlineView?.reloadData()
                self?.applyExpandedStateIfNeeded()
                self?.applyAppearanceToVisibleRows()
            }
        } else {
            applyExpandedStateIfNeeded()
            applyAppearanceToVisibleRows()
        }
    }

    private func applyExpandedStateIfNeeded() {
        guard !dataSource.isSearching, let outlineView else { return }

        let targets = expandedRelativePaths.wrappedValue
            .sorted { a, b in
                let aDepth = a.split(separator: "/").count
                let bDepth = b.split(separator: "/").count
                if aDepth != bDepth { return aDepth < bDepth }
                return a < b
            }

        for relative in targets {
            guard let item = dataSource.canonicalUrl(forRelativePath: relative) else { continue }
            outlineView.expandItem(item)
        }
    }

    private func applyAppearanceToVisibleRows() {
        guard let outlineView else { return }

        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = max(18, CGFloat(fontSize) + 6)

        let resolvedFont = NSFont(name: fontFamily, size: CGFloat(fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(fontSize), weight: .regular)
        guard outlineView.numberOfRows > 0 else { return }

        let visibleRect = outlineView.visibleRect
        let visibleRange = outlineView.rows(in: visibleRect)
        guard visibleRange.length > 0 else { return }

        let start = max(0, visibleRange.location)
        let end = min(outlineView.numberOfRows, visibleRange.location + visibleRange.length)
        guard start < end else { return }

        for row in start..<end {
            if let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView {
                cell.textField?.font = resolvedFont
            }
        }

        outlineView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: start..<end))
    }

    private func setSearchQuery(_ value: String) {
        let wasSearching = dataSource.isSearching
        dataSource.setSearchQuery(value)

        if dataSource.isSearching {
            scheduleSearch(query: value)
        } else if wasSearching {
            dataSource.resetCaches()
        }
    }

    @objc func onDoubleClick(_ sender: Any?) {
        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else { return }

        if dataSource.isDirectory(item.url) {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
            applyAppearanceToVisibleRows()
        } else {
            onOpenFile(item.url as URL)
        }
    }

    private func performOpen(for item: FileTreeItem) {
        guard let outlineView else { return }
        if dataSource.isDirectory(item.url) {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
            applyAppearanceToVisibleRows()
            return
        }

        onOpenFile(item.url as URL)
    }

    // MARK: - NSMenuDelegate

    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: "New File", action: #selector(onContextNewFile(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "New Folder", action: #selector(onContextNewFolder(_:)), keyEquivalent: "")

        if let item = clickedFileTreeItem() {
            let url = item.url as URL
            menu.addItem(.separator())
            menu.addItem(withTitle: "Open", action: #selector(onContextOpen(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Rename", action: #selector(onContextRename(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Delete", action: #selector(onContextDelete(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Show in Finder", action: #selector(onContextRevealInFinder(_:)), keyEquivalent: "")

            for menuItem in menu.items {
                menuItem.target = self
                menuItem.representedObject = url
            }
            return
        }

        for menuItem in menu.items {
            menuItem.target = self
        }
    }

    @objc private func onContextOpen(_ sender: NSMenuItem) {
        guard let item = clickedFileTreeItem() else { return }
        performOpen(for: item)
    }

    @objc private func onContextDelete(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onDeleteItem(url)
    }

    @objc private func onContextRename(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let initialName = url.lastPathComponent
        guard let newName = promptForRename(initialName: initialName) else { return }
        onRenameItem(url, newName)
    }

    @objc private func onContextRevealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onRevealInFinder(url)
    }

    @objc private func onContextNewFile(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = promptForNewItem(title: "Create New File", informativeText: "Enter a file name.") else { return }
        onCreateFile(directory, name)
    }

    @objc private func onContextNewFolder(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = promptForNewItem(title: "Create New Folder", informativeText: "Enter a folder name.") else { return }
        onCreateFolder(directory, name)
    }

    // MARK: - NSOutlineViewDelegate

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !dataSource.isSearching, let item = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        if let relative = dataSource.relativePath(for: item.url) {
            Task { @MainActor in
                await Task.yield()
                if !self.expandedRelativePaths.wrappedValue.contains(relative) {
                    self.expandedRelativePaths.wrappedValue.insert(relative)
                }
                self.applyAppearanceToVisibleRows()
            }
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !dataSource.isSearching, let item = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        if let relative = dataSource.relativePath(for: item.url) {
            Task { @MainActor in
                await Task.yield()
                if self.expandedRelativePaths.wrappedValue.contains(relative) {
                    self.expandedRelativePaths.wrappedValue.remove(relative)
                    self.expandedRelativePaths.wrappedValue = self.expandedRelativePaths.wrappedValue.filter { !$0.hasPrefix(relative + "/") }
                }
                self.applyAppearanceToVisibleRows()
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !dataSource.isSearching, let outlineView = notification.object as? NSOutlineView else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else {
            Task { @MainActor in
                await Task.yield()
                self.selectedRelativePath.wrappedValue = nil
            }
            return
        }

        if dataSource.isDirectory(item.url) {
            Task { @MainActor in
                await Task.yield()
                self.selectedRelativePath.wrappedValue = nil
            }
        } else {
            let relative = dataSource.relativePath(for: item.url)
            Task { @MainActor in
                await Task.yield()
                if self.selectedRelativePath.wrappedValue != relative {
                    self.selectedRelativePath.wrappedValue = relative
                }
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let ftItem = item as? FileTreeItem else { return nil }
        let url = ftItem.url

        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView(frame: .zero)
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = NSFont(name: self.fontFamily, size: CGFloat(self.fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(self.fontSize), weight: .regular)

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.textField = textField
            cell.imageView = imageView

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()

        cell.textField?.stringValue = dataSource.displayName(for: ftItem)
        cell.textField?.font = NSFont(name: self.fontFamily, size: CGFloat(self.fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(self.fontSize), weight: .regular)
        if let path = url.path, !path.isEmpty {
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: path)
        } else {
            if dataSource.isDirectory(url) {
                cell.imageView?.image = NSImage(named: NSImage.folderName)
            } else {
                cell.imageView?.image = NSImage(named: NSImage.multipleDocumentsName)
            }
        }

        if let relativePath = dataSource.relativePath(for: url), relativePath == selectedRelativePath.wrappedValue {
            cell.textField?.textColor = fileLabelColor(for: url) ?? .labelColor
        } else {
            cell.textField?.textColor = fileLabelColor(for: url) ?? .labelColor
        }

        return cell
    }

    // MARK: - Private

    private nonisolated static func enumerateMatches(rootURL: URL, query: String, limit: Int) -> [URL] {
        var results: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let lowerQuery = query.lowercased()

        while let next = enumerator?.nextObject() as? URL {
            if results.count >= limit { break }
            if next.lastPathComponent.lowercased().contains(lowerQuery) {
                results.append(next)
            }
        }

        return results
    }

    private nonisolated static func makeSearchWorkItem(
        rootURL: URL,
        query: String,
        limit: Int,
        onResults: @escaping ([URL]) -> Void
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            let results = Self.enumerateMatches(rootURL: rootURL, query: query, limit: limit)
            onResults(results)
        }
    }

    private func scheduleSearch(query: String) {
        let searchContext = beginSearch(query: query)

        if searchContext.query.isEmpty {
            dataSource.resetCaches()
            return
        }

        // XCTest runs the app-hosted test bundle in a way that can SIGTRAP if we spin the main
        // runloop to await debounced background work. Make search deterministic for tests by
        // performing it synchronously on the MainActor.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            runSynchronousSearch(searchContext)
            return
        }

        scheduleAsynchronousSearch(searchContext)
    }

    private struct SearchContext {
        let generation: Int
        let rootURL: URL?
        let query: String
    }

    private func beginSearch(query: String) -> SearchContext {
        searchWorkItem?.cancel()
        searchGeneration += 1
        return SearchContext(generation: searchGeneration, rootURL: lastRootURL, query: query)
    }

    private func canApplySearchResults(_ context: SearchContext) -> Bool {
        guard searchGeneration == context.generation else { return false }
        guard lastSearchQuery == context.query else { return false }
        return true
    }

    private func applySearchResults(_ results: [URL], context: SearchContext) {
        guard canApplySearchResults(context) else { return }
        let items = results.map { dataSource.canonical($0) }
        dataSource.setSearchResults(items)
        outlineView?.reloadData()
        applyAppearanceToVisibleRows()
    }

    private func runSynchronousSearch(_ context: SearchContext) {
        guard let rootURL = context.rootURL else { return }
        let results = Self.enumerateMatches(rootURL: rootURL, query: context.query, limit: 500)
        applySearchResults(results, context: context)
    }

    private func scheduleAsynchronousSearch(_ context: SearchContext) {
        guard let rootURL = context.rootURL else { return }

        let work = Self.makeSearchWorkItem(rootURL: rootURL, query: context.query, limit: 500) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                self.applySearchResults(results, context: context)
            }
        }

        searchWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func fileLabelColor(for url: NSURL) -> NSColor? {
        guard let labelNumber = try? (url as URL).resourceValues(forKeys: [.labelNumberKey]).labelNumber,
              labelNumber > 0 else { return nil }
        let colors = NSWorkspace.shared.fileLabelColors
        let index = labelNumber - 1
        guard index >= 0, index < colors.count else { return nil }
        return colors[index]
    }
}
