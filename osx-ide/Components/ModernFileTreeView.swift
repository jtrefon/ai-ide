//
//  ModernFileTreeView.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//  Modern macOS v26 file tree with liquid glass effects and native APIs
//

import SwiftUI
import AppKit

/// Modern macOS v26 file tree view with enhanced liquid glass effects
struct ModernFileTreeView: NSViewRepresentable {
    let rootURL: URL
    @Binding var searchQuery: String
    @Binding var expandedRelativePaths: Set<String>
    @Binding var selectedRelativePath: String?
    let refreshToken: Int
    let onOpenFile: (URL) -> Void

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8
        
        // Create modern outline view-based file tree with enhanced styling
        let outlineView = NSOutlineView(frame: .zero)
        outlineView.setAccessibilityIdentifier("Modern Explorer")
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.focusRingType = .none
        outlineView.allowsMultipleSelection = false
        outlineView.wantsLayer = true
        outlineView.layer?.cornerRadius = 6
        outlineView.layer?.backgroundColor = NSColor.clear.cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.onDoubleClick(_:))

        let scrollView = NSScrollView(frame: .zero)
        scrollView.setAccessibilityIdentifier("Modern Explorer")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.attach(outlineView: outlineView)
        DispatchQueue.main.async {
            context.coordinator.setRootURL(rootURL)
        }

        containerView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        let rootURL = self.rootURL
        let searchQuery = self.searchQuery
        let refreshToken = self.refreshToken

        DispatchQueue.main.async {
            coordinator.setRootURL(rootURL)
            coordinator.setSearchQuery(searchQuery)

            if coordinator.refreshToken != refreshToken {
                coordinator.refreshToken = refreshToken
                coordinator.clearCaches()
            }
        }
    }

    func makeCoordinator() -> ModernCoordinator {
        ModernCoordinator(
            expandedRelativePaths: $expandedRelativePaths,
            selectedRelativePath: $selectedRelativePath,
            onOpenFile: onOpenFile
        )
    }
}

/// Modern coordinator for the file tree with enhanced performance and macOS v26 styling
@MainActor
final class ModernCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let fileManager = FileManager.default
    private let expandedRelativePaths: Binding<Set<String>>
    private let selectedRelativePath: Binding<String?>
    private let onOpenFile: (URL) -> Void

    private weak var outlineView: NSOutlineView?

    private var rootURL: URL?
    private var searchQuery: String = ""

    private var childrenCache: [URL: [URL]] = [:]
    private var isDirectoryCache: [URL: Bool] = [:]

    private var searchResults: [URL] = []
    private var searchWorkItem: DispatchWorkItem?

    fileprivate var refreshToken: Int = 0

    init(
        expandedRelativePaths: Binding<Set<String>>,
        selectedRelativePath: Binding<String?>,
        onOpenFile: @escaping (URL) -> Void
    ) {
        self.expandedRelativePaths = expandedRelativePaths
        self.selectedRelativePath = selectedRelativePath
        self.onOpenFile = onOpenFile
    }

    func attach(outlineView: NSOutlineView) {
        self.outlineView = outlineView
    }

    func clearCaches() {
        childrenCache.removeAll()
        isDirectoryCache.removeAll()
        searchResults.removeAll()
        outlineView?.reloadData()
        if let rootURL {
            loadChildren(for: rootURL)
        }
    }

    func setRootURL(_ url: URL) {
        guard rootURL != url else { return }
        rootURL = url
        searchResults.removeAll()
        childrenCache.removeAll()
        isDirectoryCache.removeAll()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let selectedRelative = self.selectedRelativePath.wrappedValue {
                let ancestors = Self.ancestorRelativePaths(for: selectedRelative)
                if !ancestors.isEmpty {
                    self.expandedRelativePaths.wrappedValue.formUnion(ancestors)
                }
            }
            
            self.outlineView?.reloadData()
            self.loadChildren(for: url)
        }
    }

    func setSearchQuery(_ value: String) {
        guard searchQuery != value else { return }
        searchQuery = value
        scheduleSearch()
    }

    @MainActor
    @objc func onDoubleClick(_ sender: Any?) {
        guard let outlineView else { return }
        let row = outlineView.clickedRow
        guard row >= 0, let item = outlineView.item(atRow: row) else { return }

        if let url = item as? URL {
            if isDirectory(url) {
                if outlineView.isItemExpanded(url) {
                    outlineView.collapseItem(url)
                } else {
                    outlineView.expandItem(url)
                }
            } else {
                onOpenFile(url)
            }
        }
    }

    @MainActor
    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isSearching else { return }
        guard let url = notification.userInfo?["NSObject"] as? URL else { return }
        guard let relative = relativePath(for: url) else { return }
        expandedRelativePaths.wrappedValue.insert(relative)
    }

    @MainActor
    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isSearching else { return }
        guard let url = notification.userInfo?["NSObject"] as? URL else { return }
        guard let relative = relativePath(for: url) else { return }
        expandedRelativePaths.wrappedValue.remove(relative)
        expandedRelativePaths.wrappedValue = expandedRelativePaths.wrappedValue.filter { !$0.hasPrefix(relative + "/") }
    }

    @MainActor
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSearching else { return }
        guard let outlineView = notification.object as? NSOutlineView else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let url = outlineView.item(atRow: row) as? URL else {
            selectedRelativePath.wrappedValue = nil
            return
        }
        if isDirectory(url) {
            selectedRelativePath.wrappedValue = nil
            return
        }
        selectedRelativePath.wrappedValue = relativePath(for: url)
    }

    // MARK: - NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if isSearching {
            return item == nil ? searchResults.count : 0
        }

        let url: URL
        if let item {
            guard let itemURL = item as? URL else { return 0 }
            url = itemURL
        } else {
            guard let rootURL else { return 0 }
            url = rootURL
        }

        if !isDirectory(url) { return 0 }

        if let cached = childrenCache[url] {
            return cached.count
        }

        loadChildren(for: url)
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if isSearching {
            return searchResults[index]
        }

        let url: URL
        if let item {
            url = item as! URL
        } else {
            url = rootURL!
        }

        return childrenCache[url]![index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard !isSearching, let url = item as? URL else { return false }
        return isDirectory(url)
    }

    // MARK: - NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let url = item as? URL else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell: NSTableCellView

        if let existing = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = existing
        } else {
            cell = NSTableCellView(frame: .zero)
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            textField.textColor = .controlTextColor

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown

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
        }

        cell.textField?.stringValue = displayName(for: url)
        
        // Modern macOS v26 icon styling
        let iconName = getModernIconName(for: url)
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: url.lastPathComponent) {
            cell.imageView?.image = image
        }
        
        // Enhanced selection styling
        if let relativePath = relativePath(for: url), relativePath == selectedRelativePath.wrappedValue {
            cell.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            cell.textField?.textColor = .systemBlue
        } else {
            cell.layer?.backgroundColor = NSColor.clear.cgColor
            cell.textField?.textColor = .controlTextColor
        }
        
        return cell
    }

    // MARK: - Private

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scheduleSearch() {
        searchWorkItem?.cancel()

        if !isSearching {
            searchResults.removeAll()
            outlineView?.reloadData()
            if let rootURL {
                loadChildren(for: rootURL)
            }
            return
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var work: DispatchWorkItem!
        work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let rootURL = self.rootURL else { return }

            var results: [URL] = []
            let enumerator = self.fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            while let next = enumerator?.nextObject() as? URL {
                if work.isCancelled { return }
                let name = next.lastPathComponent.lowercased()
                if name.contains(query) {
                    results.append(next)
                    if results.count >= 500 { break }
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.searchResults = results
                self.outlineView?.reloadData()
            }
        }

        searchWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func displayName(for url: URL) -> String {
        if isSearching, let rootURL {
            let relative = url.path.replacingOccurrences(of: rootURL.path, with: "")
            if relative.isEmpty { return url.lastPathComponent }
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent
    }

    private func isDirectory(_ url: URL) -> Bool {
        if let cached = isDirectoryCache[url] { return cached }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        isDirectoryCache[url] = isDir
        return isDir
    }

    private func relativePath(for url: URL) -> String? {
        guard let rootURL else { return nil }
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return nil }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? nil : relative
    }

    private static func ancestorRelativePaths(for relative: String) -> [String] {
        let comps = relative.split(separator: "/")
        guard comps.count >= 2 else { return [] }
        var ancestors: [String] = []
        for i in 0..<(comps.count - 1) {
            ancestors.append(comps[0...i].joined(separator: "/"))
        }
        return ancestors
    }

    private func restoreExpandedChildrenIfNeeded(parentURL: URL) {
        guard let outlineView, let rootURL else { return }
        guard let children = childrenCache[parentURL] else { return }
        for child in children {
            guard isDirectory(child) else { continue }
            guard let rel = relativePath(for: child) else { continue }
            if expandedRelativePaths.wrappedValue.contains(rel) {
                outlineView.expandItem(child)
            }
        }

        if parentURL == rootURL, let selected = selectedRelativePath.wrappedValue, let selectedURL = url(forRelativePath: selected) {
            if let row = outlineView.row(forItem: selectedURL) as Int?, row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }
    }

    private func loadChildren(for url: URL) {
        if childrenCache[url] != nil { return }
        childrenCache[url] = []

        Task { @MainActor in
            guard let contents = try? self.fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                self.childrenCache[url] = []
                self.outlineView?.reloadItem(url, reloadChildren: true)
                return
            }

            let items: [URL] = contents.sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aIsDir != bIsDir {
                    return aIsDir && !bIsDir
                }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }

            self.childrenCache[url] = items
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                self.isDirectoryCache[item] = isDir
            }
            if url == self.rootURL {
                self.outlineView?.reloadData()
            } else {
                self.outlineView?.reloadItem(url, reloadChildren: true)
            }

            self.restoreExpandedChildrenIfNeeded(parentURL: url)
        }
    }

    private func url(forRelativePath relative: String) -> URL? {
        guard let rootURL else { return nil }
        guard !relative.isEmpty else { return rootURL }
        return rootURL.appendingPathComponent(relative)
    }
    
    private func getModernIconName(for url: URL) -> String {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDir {
            return "folder.fill"
        } else {
            return getFileIconName(for: url.lastPathComponent)
        }
    }
    
    private func getFileIconName(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx": return "square.and.arrow.up"
        case "ts", "tsx": return "square.and.arrow.up"
        case "py": return "square.and.arrow.up"
        case "html": return "square.and.arrow.up"
        case "css": return "square.and.arrow.up"
        case "json": return "curlybraces"
        case "md": return "doc.plaintext"
        default: return "doc"
        }
    }
}