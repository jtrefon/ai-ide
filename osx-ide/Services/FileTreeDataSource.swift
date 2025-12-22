//
//  FileTreeDataSource.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import AppKit

/// A stable wrapper for file system items to ensure safe identity in NSOutlineView
final class FileTreeItem: NSObject, Sendable {
    let url: NSURL
    let path: String
    
    init(url: NSURL) {
        self.url = url
        self.path = url.path ?? ""
        super.init()
    }
    
    override var hash: Int { path.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? FileTreeItem else { return false }
        return path == other.path
    }
    
    var asURL: URL { url as URL }
}

/// Unified data source and logic manager for the file tree
@MainActor
class FileTreeDataSource: NSObject, NSOutlineViewDataSource {
    private let fileManager = FileManager.default
    private var rootURL: FileTreeItem?
    private var searchQuery: String = ""
    private var loadGeneration: Int = 0
    
    private var childrenCache: [URL: [FileTreeItem]] = [:]
    private var isDirectoryCache: [URL: Bool] = [:]
    private var itemCache: [URL: FileTreeItem] = [:]
    private var searchResults: [FileTreeItem] = []
    
    // Stable sentinels to avoid creating new objects in transition states
    private lazy var fallbackItem = FileTreeItem(url: NSURL(fileURLWithPath: "/dev/null"))
    
    weak var outlineView: NSOutlineView?
    var onDataChanged: ((NSURL?) -> Void)?
    
    // MARK: - Properties
    
    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Configuration
    
    func setRootURL(_ url: URL) {
        let item = canonical(url)
        guard rootURL?.path != item.path else { return }
        
        loadGeneration += 1
        rootURL = item
        resetCaches(includeItemCache: false)
        
        // Prime the root load
        loadChildren(for: item)
    }
    
    func setSearchQuery(_ query: String) {
        guard searchQuery != query else { return }
        let wasSearching = isSearching
        searchQuery = query
        
        if wasSearching != isSearching {
            searchResults.removeAll()
            outlineView?.reloadData()
        }
    }
    
    func resetCaches(includeItemCache: Bool = false) {
        childrenCache.removeAll()
        isDirectoryCache.removeAll()
        searchResults.removeAll()
        if includeItemCache {
            itemCache.removeAll()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.outlineView?.reloadData()
        }
    }
    
    func canonical(_ url: URL) -> FileTreeItem {
        let standardized = url.standardized
        if let cached = itemCache[standardized] { return cached }
        let item = FileTreeItem(url: standardized as NSURL)
        itemCache[standardized] = item
        return item
    }
    
    // MARK: - File Info
    
    func isDirectory(_ url: NSURL) -> Bool {
        let pathURL = url as URL
        if let cached = isDirectoryCache[pathURL] { return cached }
        let isDir = (try? pathURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        isDirectoryCache[pathURL] = isDir
        return isDir
    }
    
    func relativePath(for url: NSURL) -> String? {
        guard let rootURL = self.rootURL else { return nil }
        let rootPath = rootURL.path
        let path = url.path ?? ""
        guard path.hasPrefix(rootPath) else { return nil }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? nil : relative
    }
    
    func url(forRelativePath relative: String) -> URL? {
        guard let rootItem = self.rootURL else { return nil }
        let rootURL = rootItem.asURL
        guard !relative.isEmpty else { return rootURL }
        return rootURL.appendingPathComponent(relative)
    }
    
    func canonicalUrl(forRelativePath relative: String) -> FileTreeItem? {
        guard let url = url(forRelativePath: relative) else { return nil }
        return canonical(url)
    }
    
    func displayName(for item: FileTreeItem) -> String {
        if isSearching, let rootURL = self.rootURL {
            let relative = item.path.replacingOccurrences(of: rootURL.path, with: "")
            if relative.isEmpty { return item.url.lastPathComponent! }
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return item.url.lastPathComponent!
    }
    
    // MARK: - Data Loading
    
    func loadChildren(for item: FileTreeItem) {
        let pathURL = item.asURL
        if childrenCache[pathURL] != nil { return }
        childrenCache[pathURL] = []
        
        let generation = self.loadGeneration
        Task { @MainActor in
            guard let contents = try? self.fileManager.contentsOfDirectory(at: pathURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                self.childrenCache[pathURL] = []
                DispatchQueue.main.async {
                    self.outlineView?.reloadItem(item, reloadChildren: true)
                }
                return
            }
            
            let resultItems: [FileTreeItem] = contents.sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aIsDir != bIsDir { return aIsDir && !bIsDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }.map { self.canonical($0) }
            
            // Invalidation check: did the root change while we were loading?
            guard self.loadGeneration == generation else { return }
            
            self.childrenCache[pathURL] = resultItems
            for subItem in resultItems {
                let itemPath = subItem.asURL
                let isDir = (try? itemPath.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                self.isDirectoryCache[itemPath] = isDir
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let ov = self.outlineView, self.loadGeneration == generation else { return }
                
                if item.path == self.rootURL?.path {
                    ov.reloadData()
                } else if ov.isItemExpanded(item) {
                    ov.reloadItem(item, reloadChildren: true)
                }
                
                self.onDataChanged?(item.url)
            }
        }
    }
    
    func setSearchResults(_ results: [FileTreeItem]) {
        self.searchResults = results
        self.outlineView?.reloadData()
    }
    
    // MARK: - NSOutlineViewDataSource
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if isSearching {
            return item == nil ? searchResults.count : 0
        }
        
        let targetItem: FileTreeItem
        if let item {
            guard let ftItem = item as? FileTreeItem else { return 0 }
            targetItem = ftItem
        } else {
            guard let root = self.rootURL else { return 0 }
            targetItem = root
        }
        
        let pathURL = targetItem.asURL
        if !isDirectory(targetItem.url) { return 0 }
        if let cached = childrenCache[pathURL] { return cached.count }
        
        loadChildren(for: targetItem)
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if isSearching {
            guard index < searchResults.count else { return fallbackItem }
            return searchResults[index]
        }
        
        let targetItem: FileTreeItem
        if let item {
            targetItem = item as! FileTreeItem
        } else {
            guard let root = self.rootURL else { return fallbackItem }
            targetItem = root
        }
        
        guard let children = childrenCache[targetItem.asURL], index < children.count else {
            return fallbackItem
        }
        return children[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard !isSearching, let ftItem = item as? FileTreeItem, ftItem != fallbackItem else { return false }
        return isDirectory(ftItem.url)
    }
}
