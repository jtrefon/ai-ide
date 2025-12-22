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
    var refreshToken: Int = 0
    private var lastRootPath: String?
    private var lastSearchQuery: String = ""

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

    func update(rootURL: URL, searchQuery: String, refreshToken: Int) {
        var needsReload = false

        if self.refreshToken != refreshToken {
            self.refreshToken = refreshToken
            dataSource.resetCaches()
            needsReload = true
        }

        let rootPath = rootURL.standardizedFileURL.path
        if lastRootPath != rootPath {
            lastRootPath = rootPath
            dataSource.setRootURL(rootURL)
            needsReload = true
        }

        if lastSearchQuery != searchQuery {
            lastSearchQuery = searchQuery
            setSearchQuery(searchQuery)
            needsReload = true
        }

        if needsReload {
            outlineView?.reloadData()
        }
    }

    private func setSearchQuery(_ value: String) {
        let wasSearching = dataSource.isSearching
        dataSource.setSearchQuery(value)
        
        if wasSearching != dataSource.isSearching {
            scheduleSearch(query: value)
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
            DispatchQueue.main.async {
                if !self.expandedRelativePaths.wrappedValue.contains(relative) {
                    self.expandedRelativePaths.wrappedValue.insert(relative)
                }
            }
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !dataSource.isSearching, let item = notification.userInfo?["NSObject"] as? FileTreeItem else { return }
        if let relative = dataSource.relativePath(for: item.url) {
            DispatchQueue.main.async {
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
            DispatchQueue.main.async {
                self.selectedRelativePath.wrappedValue = nil
            }
            return
        }
        
        if dataSource.isDirectory(item.url) {
            DispatchQueue.main.async {
                self.selectedRelativePath.wrappedValue = nil
            }
        } else {
            let relative = dataSource.relativePath(for: item.url)
            DispatchQueue.main.async {
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

    private func scheduleSearch(query: String) {
        searchWorkItem?.cancel()
        if query.isEmpty {
            dataSource.resetCaches()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, let rootItem = self.dataSource.canonicalUrl(forRelativePath: "") else { return }
            var results: [FileTreeItem] = []
            let enumerator = FileManager.default.enumerator(at: rootItem.url as URL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            let lowerQuery = query.lowercased()
            
            while let next = enumerator?.nextObject() as? URL {
                if results.count >= 500 { break }
                if next.lastPathComponent.lowercased().contains(lowerQuery) {
                    results.append(self.dataSource.canonical(next))
                }
            }
            
            Task { @MainActor in
                self.dataSource.setSearchResults(results)
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
