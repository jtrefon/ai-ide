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
    let onCreateFile: (URL, String) -> Void
    let onCreateFolder: (URL, String) -> Void
    let onDeleteItem: (URL) -> Void
    let onRenameItem: (URL, String) -> Void
    let onRevealInFinder: (URL) -> Void
    let fontSize: Double
    let fontFamily: String

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()

        let outlineView = NSOutlineView(frame: .zero)
        outlineView.setAccessibilityIdentifier("Modern Explorer")
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .default
        outlineView.rowHeight = max(18, CGFloat(fontSize) + 6)
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
        outlineView.doubleAction = #selector(ModernFileTreeCoordinator.onDoubleClick(_:))

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
            refreshToken: refreshToken,
            fontSize: fontSize,
            fontFamily: fontFamily
        )
    }

    func makeCoordinator() -> ModernFileTreeCoordinator {
        ModernFileTreeCoordinator(
            configuration: ModernFileTreeCoordinator.Configuration(
                expandedRelativePaths: $expandedRelativePaths,
                selectedRelativePath: $selectedRelativePath,
                onOpenFile: onOpenFile,
                onCreateFile: onCreateFile,
                onCreateFolder: onCreateFolder,
                onDeleteItem: onDeleteItem,
                onRenameItem: onRenameItem,
                onRevealInFinder: onRevealInFinder
            )
        )
    }
}
