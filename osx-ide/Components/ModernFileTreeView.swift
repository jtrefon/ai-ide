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
        let containerView = NSVisualEffectView()
        containerView.material = .sidebar
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8

        let outlineView = NSOutlineView(frame: .zero)
        outlineView.setAccessibilityIdentifier("Modern Explorer")
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .medium
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.focusRingType = .none
        outlineView.allowsMultipleSelection = false
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.style = .sourceList
        outlineView.wantsLayer = true
        outlineView.layer?.cornerRadius = 6
        outlineView.backgroundColor = .clear

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
        scrollView.wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.verticalScroller = LiquidGlassScroller()

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

    init(
        expandedRelativePaths: Binding<Set<String>>,
        selectedRelativePath: Binding<String?>,
        onOpenFile: @escaping (URL) -> Void
    ) {
        self.expandedRelativePaths = expandedRelativePaths
        self.selectedRelativePath = selectedRelativePath
        self.onOpenFile = onOpenFile
        super.init()
        
        dataSource.onDataChanged = { [weak self] parentURL in
            self?.restoreExpandedChildrenIfNeeded(parentURL: parentURL)
        }
    }

    func attach(outlineView: NSOutlineView) {
        self.outlineView = outlineView
        dataSource.outlineView = outlineView
    }

    func update(rootURL: URL, searchQuery: String, refreshToken: Int) {
        if self.refreshToken != refreshToken {
            self.refreshToken = refreshToken
            dataSource.resetCaches()
        }
        
        dataSource.setRootURL(rootURL)
        setSearchQuery(searchQuery)
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
        guard row >= 0, let item = outlineView.item(atRow: row) as? NSURL else { return }

        if dataSource.isDirectory(item) {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
        } else {
            onOpenFile(item as URL)
        }
    }

    // MARK: - NSOutlineViewDelegate

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !dataSource.isSearching, let url = notification.userInfo?["NSObject"] as? NSURL else { return }
        if let relative = dataSource.relativePath(for: url) {
            Task { @MainActor in
                expandedRelativePaths.wrappedValue.insert(relative)
            }
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !dataSource.isSearching, let url = notification.userInfo?["NSObject"] as? NSURL else { return }
        if let relative = dataSource.relativePath(for: url) {
            Task { @MainActor in
                expandedRelativePaths.wrappedValue.remove(relative)
                expandedRelativePaths.wrappedValue = expandedRelativePaths.wrappedValue.filter { !$0.hasPrefix(relative + "/") }
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !dataSource.isSearching, let outlineView = notification.object as? NSOutlineView else { return }
        let row = outlineView.selectedRow
        guard row >= 0, let url = outlineView.item(atRow: row) as? NSURL else {
            Task { @MainActor in
                selectedRelativePath.wrappedValue = nil
            }
            return
        }
        
        if dataSource.isDirectory(url) {
            Task { @MainActor in
                selectedRelativePath.wrappedValue = nil
            }
        } else {
            let relative = dataSource.relativePath(for: url)
            Task { @MainActor in
                selectedRelativePath.wrappedValue = relative
            }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let url = item as? NSURL else { return nil }

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

        cell.textField?.stringValue = dataSource.displayName(for: url)
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: url.path!)
        
        if let relativePath = dataSource.relativePath(for: url), relativePath == selectedRelativePath.wrappedValue {
            cell.textField?.textColor = .systemBlue
        } else {
            cell.textField?.textColor = fileLabelColor(for: url) ?? .controlTextColor
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
            guard let self, let rootURL = self.dataSource.url(forRelativePath: "") else { return }
            var results: [NSURL] = []
            let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            let lowerQuery = query.lowercased()
            
            while let next = enumerator?.nextObject() as? URL {
                if results.count >= 500 { break }
                if next.lastPathComponent.lowercased().contains(lowerQuery) {
                    results.append(next as NSURL)
                }
            }

            Task { @MainActor in
                self.dataSource.setSearchResults(results)
            }
        }

        searchWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func restoreExpandedChildrenIfNeeded(parentURL: NSURL?) {
        guard let outlineView, let parentURL = parentURL else { return }
        // Note: Simple logic to restore expansion state when data is loaded
        // In a real app, this would recursively check children
        if parentURL == dataSource.url(forRelativePath: "") as NSURL? {
            // Root loaded, could select item
            if let selected = selectedRelativePath.wrappedValue, let url = dataSource.canonicalUrl(forRelativePath: selected) {
                let row = outlineView.row(forItem: url)
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            }
        }
    }

    private func fileLabelColor(for url: NSURL) -> NSColor? {
        guard let labelNumber = try? (url as URL).resourceValues(forKeys: [.labelNumberKey]).labelNumber,
              labelNumber > 0 else { return nil }
        return NSWorkspace.shared.fileLabelColors[labelNumber - 1]
    }
}
