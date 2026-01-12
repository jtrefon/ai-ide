import SwiftUI
import AppKit

/// Modern coordinator for the file tree focusing on UI events and state bridging
@MainActor
final class ModernFileTreeCoordinator: NSObject, NSOutlineViewDelegate, NSMenuDelegate {
    let dataSource = FileTreeDataSource()
    
    // Specialized coordinators
    private let dialogCoordinator: FileTreeDialogCoordinator
    private let searchCoordinator: FileTreeSearchCoordinator
    private var appearanceCoordinator: FileTreeAppearanceCoordinator

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
    private var refreshToken: Int = 0
    private var lastRootPath: String?
    private var lastRootURL: URL?
    private var lastSearchQuery: String = ""
    private var lastShowHiddenFiles: Bool = false
    private var fontSize: Double = 13
    private var fontFamily: String = "SF Mono"
    private var pendingSearchTask: Task<Void, Never>?
    private var searchGeneration: Int = 0

    init(configuration: Configuration) {
        // Initialize specialized coordinators
        self.dialogCoordinator = FileTreeDialogCoordinator()
        self.searchCoordinator = FileTreeSearchCoordinator(dataSource: dataSource)
        self.appearanceCoordinator = FileTreeAppearanceCoordinator(outlineView: NSOutlineView()) // Temporary, will be updated in attach
        
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
        
        // Update appearance coordinator with the outline view
        appearanceCoordinator = FileTreeAppearanceCoordinator(outlineView: outlineView)
        
        outlineView.dataSource = dataSource
        outlineView.delegate = self
        
        // Set up contextual menu with delegate
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu
        
        outlineView.target = self
        outlineView.doubleAction = #selector(onDoubleClick)
        
        // Apply initial appearance
        appearanceCoordinator.applyAppearanceToVisibleRows()
    }

    private func clickedFileTreeItem() -> FileTreeItem? {
        guard let outlineView else { return nil }
        let row = outlineView.clickedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileTreeItem
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

    }
    
    private func setSearchQuery(_ value: String) {
        searchCoordinator.setSearchQuery(value)
    }
    
    @objc func onDoubleClick(_ sender: Any?) {
        guard let item = clickedFileTreeItem() else { return }
        performOpen(for: item)
    }
    
    private func performOpen(for item: FileTreeItem) {
        onOpenFile(item.url as URL)
    }
    
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        guard let item = clickedFileTreeItem() else { return }
        let url = item.url
        
        // Add file operations
        let openItem = NSMenuItem(title: NSLocalizedString("file_tree.context.open", comment: ""), action: #selector(onContextOpen(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = url
        menu.addItem(openItem)
        
        let renameItem = NSMenuItem(title: NSLocalizedString("file_tree.context.rename", comment: ""), action: #selector(onContextRename(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = url
        menu.addItem(renameItem)
        
        let deleteItem = NSMenuItem(title: NSLocalizedString("file_tree.context.delete", comment: ""), action: #selector(onContextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = url
        menu.addItem(deleteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let revealItem = NSMenuItem(title: NSLocalizedString("file_tree.context.show_in_finder", comment: ""), action: #selector(onContextRevealInFinder(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.representedObject = url
        menu.addItem(revealItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let newFileItem = NSMenuItem(title: NSLocalizedString("file_tree.context.new_file", comment: ""), action: #selector(onContextNewFile(_:)), keyEquivalent: "")
        newFileItem.target = self
        menu.addItem(newFileItem)
        
        let newFolderItem = NSMenuItem(title: NSLocalizedString("file_tree.context.new_folder", comment: ""), action: #selector(onContextNewFolder(_:)), keyEquivalent: "")
        newFolderItem.target = self
        menu.addItem(newFolderItem)
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
        guard let newName = dialogCoordinator.promptForRename(initialName: initialName) else { return }
        onRenameItem(url, newName)
    }

    @objc private func onContextRevealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onRevealInFinder(url)
    }

    @objc private func onContextNewFile(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = dialogCoordinator.promptForNewItem(
            title: NSLocalizedString("file_tree.create_file.title", comment: ""),
            informativeText: NSLocalizedString("file_tree.create_file.info", comment: "")
        ) else { return }
        onCreateFile(directory, name)
    }

    @objc private func onContextNewFolder(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = dialogCoordinator.promptForNewItem(
            title: NSLocalizedString("file_tree.create_folder.title", comment: ""),
            informativeText: NSLocalizedString("file_tree.create_folder.info", comment: "")
        ) else { return }
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
        pendingSearchTask?.cancel()
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

        pendingSearchTask?.cancel()
        pendingSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }

            let results = await Task.detached(priority: .userInitiated) {
                Self.enumerateMatches(rootURL: rootURL, query: context.query, limit: 500)
            }.value

            await MainActor.run {
                self.applySearchResults(results, context: context)
            }
        }
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

// MARK: - Dialog Handling

private extension ModernFileTreeCoordinator {
    
    /// Prompts user for renaming an item
    func promptForRename(initialName: String) -> String? {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("file_tree.rename.title", comment: "")
        alert.informativeText = NSLocalizedString("file_tree.rename.info", comment: "")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("file_tree.rename.button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: ""))

        let textField = NSTextField(string: initialName)
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    /// Prompts user for creating a new item
    func promptForNewItem(title: String, informativeText: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("file_tree.create.button", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("common.cancel", comment: ""))

        let textField = NSTextField(string: "")
        textField.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = textField

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }

        let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
