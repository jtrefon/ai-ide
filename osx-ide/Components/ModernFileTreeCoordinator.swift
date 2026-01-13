import SwiftUI
import AppKit

/// Modern coordinator for the file tree focusing on UI events and state bridging
struct ModernFileTreeCoordinatorConfiguration {
    let expandedRelativePaths: Binding<Set<String>>
    let selectedRelativePath: Binding<String?>
    let onOpenFile: (URL) -> Void
    let onCreateFile: (URL, String) -> Void
    let onCreateFolder: (URL, String) -> Void
    let onDeleteItem: (URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onRevealInFinder: (URL) -> Void
}

@MainActor
final class ModernFileTreeCoordinator: NSObject, NSOutlineViewDelegate, NSMenuDelegate {
    let dataSource = FileTreeDataSource()
    
    // Specialized coordinators
    private let dialogCoordinator: FileTreeDialogCoordinator
    private let searchCoordinator: FileTreeSearchCoordinator
    private var appearanceCoordinator: FileTreeAppearanceCoordinator

    typealias Configuration = ModernFileTreeCoordinatorConfiguration

    private let configuration: Configuration
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

    private func performDeferredUIUpdate(_ work: @MainActor @escaping () -> Void) {
        Task { @MainActor in
            await Task.yield()
            work()
        }
    }

    init(configuration: Configuration) {
        self.dialogCoordinator = FileTreeDialogCoordinator()
        self.searchCoordinator = FileTreeSearchCoordinator(dataSource: dataSource)
        self.appearanceCoordinator = Self.makePlaceholderAppearanceCoordinator()

        self.configuration = configuration
        super.init()
    }

    private static func makePlaceholderAppearanceCoordinator() -> FileTreeAppearanceCoordinator {
        FileTreeAppearanceCoordinator(outlineView: NSOutlineView())
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

    func update(
        rootURL: URL,
        parameters: UpdateParameters
    ) {
        var needsReload = false

        if self.fontSize != parameters.fontSize || self.fontFamily != parameters.fontFamily {
            self.fontSize = parameters.fontSize
            self.fontFamily = parameters.fontFamily
            needsReload = true
        }

        if self.refreshToken != parameters.refreshToken {
            self.refreshToken = parameters.refreshToken
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

        if lastSearchQuery != parameters.searchQuery {
            lastSearchQuery = parameters.searchQuery
            setSearchQuery(parameters.searchQuery)
            needsReload = true
        }

        if lastShowHiddenFiles != parameters.showHiddenFiles {
            lastShowHiddenFiles = parameters.showHiddenFiles
            dataSource.setShowHiddenFiles(parameters.showHiddenFiles)
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

        let targets = configuration.expandedRelativePaths.wrappedValue
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
        _ = outlineView

        appearanceCoordinator.applyAppearanceToVisibleRows()
    }

    struct UpdateParameters {
        let searchQuery: String
        let showHiddenFiles: Bool
        let refreshToken: Int
        let fontSize: Double
        let fontFamily: String
    }
    
    private func setSearchQuery(_ value: String) {
        searchCoordinator.setSearchQuery(value)
    }
    
    @objc func onDoubleClick(_ _: Any?) {
        guard let item = clickedFileTreeItem() else { return }
        performOpen(for: item)
    }
    
    private func performOpen(for item: FileTreeItem) {
        configuration.onOpenFile(item.url as URL)
    }
    
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let item = clickedFileTreeItem() else { return }
        let url = item.url

        addFileActionItems(menu, url: url)
        menu.addItem(NSMenuItem.separator())
        addRevealItem(menu, url: url)
        menu.addItem(NSMenuItem.separator())
        addCreateItems(menu)
    }

    private func addFileActionItems(_ menu: NSMenu, url: NSURL) {
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.open", comment: ""),
            action: #selector(onContextOpen(_:)),
            representedObject: url
        ))
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.rename", comment: ""),
            action: #selector(onContextRename(_:)),
            representedObject: url
        ))
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.delete", comment: ""),
            action: #selector(onContextDelete(_:)),
            representedObject: url
        ))
    }

    private func addRevealItem(_ menu: NSMenu, url: NSURL) {
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.show_in_finder", comment: ""),
            action: #selector(onContextRevealInFinder(_:)),
            representedObject: url
        ))
    }

    private func addCreateItems(_ menu: NSMenu) {
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.new_file", comment: ""),
            action: #selector(onContextNewFile(_:))
        ))
        menu.addItem(makeMenuItem(
            title: NSLocalizedString("file_tree.context.new_folder", comment: ""),
            action: #selector(onContextNewFolder(_:))
        ))
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        representedObject: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }
    
    @objc private func onContextOpen(_ sender: NSMenuItem) {
        guard let item = clickedFileTreeItem() else { return }
        performOpen(for: item)
    }

    @objc private func onContextDelete(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        configuration.onDeleteItem(url)
    }

    @objc private func onContextRename(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let initialName = url.lastPathComponent
        guard let newName = dialogCoordinator.promptForRename(initialName: initialName) else { return }
        configuration.onRenameItem(url, newName)
    }

    @objc private func onContextRevealInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        configuration.onRevealInFinder(url)
    }

    @objc private func onContextNewFile(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = dialogCoordinator.promptForNewItem(
            title: NSLocalizedString("file_tree.create_file.title", comment: ""),
            informativeText: NSLocalizedString("file_tree.create_file.info", comment: "")
        ) else { return }
        configuration.onCreateFile(directory, name)
    }

    @objc private func onContextNewFolder(_ sender: NSMenuItem) {
        guard let directory = directoryForCreate() else { return }
        guard let name = dialogCoordinator.promptForNewItem(
            title: NSLocalizedString("file_tree.create_folder.title", comment: ""),
            informativeText: NSLocalizedString("file_tree.create_folder.info", comment: "")
        ) else { return }
        configuration.onCreateFolder(directory, name)
    }

    // MARK: - NSOutlineViewDelegate

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !dataSource.isSearching, let item = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        if let relative = dataSource.relativePath(for: item.url) {
            performDeferredUIUpdate {
                if !self.configuration.expandedRelativePaths.wrappedValue.contains(relative) {
                    self.configuration.expandedRelativePaths.wrappedValue.insert(relative)
                }
                self.applyAppearanceToVisibleRows()
            }
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !dataSource.isSearching, let item = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        if let relative = dataSource.relativePath(for: item.url) {
            performDeferredUIUpdate {
                if self.configuration.expandedRelativePaths.wrappedValue.contains(relative) {
                    self.configuration.expandedRelativePaths.wrappedValue.remove(relative)
                    self.configuration.expandedRelativePaths.wrappedValue = self.configuration.expandedRelativePaths.wrappedValue
                        .filter { !$0.hasPrefix(relative + "/") }
                }
                self.applyAppearanceToVisibleRows()
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !dataSource.isSearching, let outlineView = notification.object as? NSOutlineView else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let item = outlineView.item(atRow: row) as? FileTreeItem else {
            performDeferredUIUpdate {
                self.configuration.selectedRelativePath.wrappedValue = nil
            }
            return
        }

        if dataSource.isDirectory(item.url) {
            performDeferredUIUpdate {
                self.configuration.selectedRelativePath.wrappedValue = nil
            }
        } else {
            let relative = dataSource.relativePath(for: item.url)
            performDeferredUIUpdate {
                if self.configuration.selectedRelativePath.wrappedValue != relative {
                    self.configuration.selectedRelativePath.wrappedValue = relative
                }
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let ftItem = item as? FileTreeItem else { return nil }
        let url = ftItem.url

        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView = outlineView.makeView(
                withIdentifier: identifier, 
                owner: nil
            ) as? NSTableCellView ?? {
            let cell = NSTableCellView(frame: .zero)
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = NSFont(
                name: self.fontFamily,
                size: CGFloat(self.fontSize)
            ) ?? NSFont.systemFont(
                ofSize: CGFloat(self.fontSize),
                weight: .regular
            )

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

        cell.textField?.stringValue = (url as URL).lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: (url as URL).path)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon

        if let relativePath = dataSource.relativePath(for: url), relativePath == configuration.selectedRelativePath.wrappedValue {
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
