//
//  ModernFileTreeView.swift
//  osx-ide
//
//  Created by Jack Trefon on 20/12/2025.
//  Modern macOS v26 file tree with native APIs
//

import SwiftUI
import AppKit

/// Modern macOS v26 file tree view
struct ModernFileTreeView: NSViewRepresentable {
    let rootURL: URL
    @Binding var searchQuery: String
    @Binding var expandedRelativePaths: Set<String>
    @Binding var selectedRelativePath: String?
    let showHiddenFiles: Bool
    let refreshToken: Int
    let onOpenFile: (URL) -> Void

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        let outlineView = NSOutlineView(frame: .zero)
        outlineView.setAccessibilityIdentifier("Modern Explorer")
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.focusRingType = .none
        outlineView.allowsMultipleSelection = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = .textBackgroundColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator.dataSource
        outlineView.target = context.coordinator
        outlineView.doubleAction = #selector(ModernCoordinator.onDoubleClick(_:))

        let scrollView = NSScrollView(frame: .zero)
        scrollView.setAccessibilityIdentifier("Modern Explorer")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        context.coordinator.attach(outlineView: outlineView)
        
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
        
        coordinator.update(
            rootURL: rootURL,
            searchQuery: searchQuery,
            showHiddenFiles: showHiddenFiles,
            refreshToken: refreshToken
        )
    }

    func makeCoordinator() -> ModernCoordinator {
        ModernCoordinator(
            expandedRelativePaths: $expandedRelativePaths,
            selectedRelativePath: $selectedRelativePath,
            onOpenFile: onOpenFile
        )
    }
}

/// Modern coordinator for the file tree focusing on UI events and state bridging
@MainActor
final class ModernCoordinator: NSObject, NSOutlineViewDelegate {
    let dataSource = FileTreeDataSource()
    
    private let expandedRelativePaths: Binding<Set<String>>
    private let selectedRelativePath: Binding<String?>
    private let onOpenFile: (URL) -> Void
    private weak var outlineView: NSOutlineView?
    private var searchWorkItem: DispatchWorkItem?
    private var searchGeneration: Int = 0
    var refreshToken: Int = 0
    private var lastRootPath: String?
    private var lastRootURL: URL?
    private var lastSearchQuery: String = ""
    private var lastShowHiddenFiles: Bool = false

    init(
        expandedRelativePaths: Binding<Set<String>>,
        selectedRelativePath: Binding<String?>,
        onOpenFile: @escaping (URL) -> Void
    ) {
        self.expandedRelativePaths = expandedRelativePaths
        self.selectedRelativePath = selectedRelativePath
        self.onOpenFile = onOpenFile
        super.init()
    }

    func attach(outlineView: NSOutlineView) {
        self.outlineView = outlineView
        dataSource.outlineView = outlineView
    }

    func update(rootURL: URL, searchQuery: String, showHiddenFiles: Bool, refreshToken: Int) {
        var needsReload = false

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
            }
        }
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
        } else {
            onOpenFile(item.url as URL)
        }
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
            textField.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            
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
        searchWorkItem?.cancel()
        searchGeneration += 1
        let currentGeneration = searchGeneration
        let rootURLSnapshot = lastRootURL
        let querySnapshot = query

        if query.isEmpty {
            dataSource.resetCaches()
            return
        }

        // XCTest runs the app-hosted test bundle in a way that can SIGTRAP if we spin the main
        // runloop to await debounced background work. Make search deterministic for tests by
        // performing it synchronously on the MainActor.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            guard let rootURL = rootURLSnapshot else { return }
            let results = Self.enumerateMatches(rootURL: rootURL, query: querySnapshot, limit: 500)

            guard self.searchGeneration == currentGeneration else { return }
            guard self.lastSearchQuery == querySnapshot else { return }
            let items = results.map { self.dataSource.canonical($0) }
            self.dataSource.setSearchResults(items)
            self.outlineView?.reloadData()
            return
        }

        guard let rootURL = rootURLSnapshot else { return }

        let work = Self.makeSearchWorkItem(rootURL: rootURL, query: querySnapshot, limit: 500) { [weak self] results in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.searchGeneration == currentGeneration else { return }
                guard self.lastSearchQuery == querySnapshot else { return }
                let items = results.map { self.dataSource.canonical($0) }
                self.dataSource.setSearchResults(items)
                self.outlineView?.reloadData()
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
