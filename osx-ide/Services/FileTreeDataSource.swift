//
//  FileTreeDataSource.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import Foundation
import AppKit

/// Unified data source and logic manager for the file tree
@MainActor
class FileTreeDataSource: NSObject, NSOutlineViewDataSource {
    private let fileManager = FileManager.default
    private var rootURL: NSURL?
    private var searchQuery: String = ""
    
    private var childrenCache: [NSURL: [NSURL]] = [:]
    private var isDirectoryCache: [NSURL: Bool] = [:]
    private var urlCache: [URL: NSURL] = [:]
    private var searchResults: [NSURL] = []
    
    weak var outlineView: NSOutlineView?
    var onDataChanged: ((NSURL?) -> Void)?
    
    // MARK: - Properties
    
    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Configuration
    
    func setRootURL(_ url: URL) {
        let nsURL = canonical(url)
        guard rootURL != nsURL else { return }
        rootURL = nsURL
        resetCaches()
        loadChildren(for: nsURL)
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
    
    func resetCaches() {
        childrenCache.removeAll()
        isDirectoryCache.removeAll()
        urlCache.removeAll()
        searchResults.removeAll()
        outlineView?.reloadData()
    }
    
    private func canonical(_ url: URL) -> NSURL {
        let standardized = url.standardized
        if let cached = urlCache[standardized] { return cached }
        let nsURL = standardized as NSURL
        urlCache[standardized] = nsURL
        return nsURL
    }
    
    // MARK: - File Info
    
    func isDirectory(_ url: NSURL) -> Bool {
        if let cached = isDirectoryCache[url] { return cached }
        let isDir = (try? (url as URL).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        isDirectoryCache[url] = isDir
        return isDir
    }
    
    func relativePath(for url: NSURL) -> String? {
        guard let rootURL = self.rootURL else { return nil }
        let rootPath = rootURL.standardized?.path ?? rootURL.path!
        let path = url.standardized?.path ?? url.path!
        guard path.hasPrefix(rootPath) else { return nil }
        var relative = String(path.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative.isEmpty ? nil : relative
    }
    
    func url(forRelativePath relative: String) -> URL? {
        guard let rootURL = self.rootURL as URL? else { return nil }
        guard !relative.isEmpty else { return rootURL }
        return rootURL.appendingPathComponent(relative)
    }
    
    func canonicalUrl(forRelativePath relative: String) -> NSURL? {
        guard let url = url(forRelativePath: relative) else { return nil }
        return canonical(url)
    }
    
    func displayName(for url: NSURL) -> String {
        if isSearching, let rootURL {
            let relative = url.path!.replacingOccurrences(of: rootURL.path!, with: "")
            if relative.isEmpty { return url.lastPathComponent! }
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return url.lastPathComponent!
    }
    
    // MARK: - Data Loading
    
    func loadChildren(for url: NSURL) {
        if childrenCache[url] != nil { return }
        childrenCache[url] = []
        
        Task { @MainActor in
            guard let contents = try? self.fileManager.contentsOfDirectory(at: url as URL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                self.childrenCache[url] = []
                self.outlineView?.reloadItem(url, reloadChildren: true)
                return
            }
            
            let items: [NSURL] = contents.sorted { a, b in
                let aIsDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bIsDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aIsDir != bIsDir { return aIsDir && !bIsDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }.map { self.canonical($0) }
            
            // Check if we are still relevant
            guard self.rootURL != nil else { return }
            
            self.childrenCache[url] = items
            for item in items {
                let isDir = (try? (item as URL).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                self.isDirectoryCache[item] = isDir
            }
            
            if url == self.rootURL {
                self.outlineView?.reloadData()
            } else {
                self.outlineView?.reloadItem(url, reloadChildren: true)
            }
            
            self.onDataChanged?(url)
        }
    }
    
    func setSearchResults(_ results: [NSURL]) {
        self.searchResults = results
        self.outlineView?.reloadData()
    }
    
    // MARK: - NSOutlineViewDataSource
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if isSearching {
            return item == nil ? searchResults.count : 0
        }
        
        let url: NSURL
        if let item {
            guard let itemURL = item as? NSURL else { return 0 }
            url = itemURL
        } else {
            guard let rootURL = self.rootURL else { return 0 }
            url = rootURL
        }
        
        if !isDirectory(url) { return 0 }
        if let cached = childrenCache[url] { return cached.count }
        
        loadChildren(for: url)
        return 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if isSearching {
            guard index < searchResults.count else { return NSURL(fileURLWithPath: "/") }
            return searchResults[index]
        }
        
        let url: NSURL
        if let item {
            url = item as! NSURL
        } else {
            guard let rootURL = self.rootURL else { return NSURL(fileURLWithPath: "/") }
            url = rootURL
        }
        
        return childrenCache[url]?[index] ?? NSURL(fileURLWithPath: "/")
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard !isSearching, let url = item as? NSURL else { return false }
        return isDirectory(url)
    }
}
