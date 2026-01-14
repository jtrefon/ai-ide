//
//  FileTreeSearchCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation
import SwiftUI

/// Handles search functionality for the file tree
@MainActor
final class FileTreeSearchCoordinator {
    private weak var dataSource: FileTreeDataSource?
    private var pendingSearchTask: Task<Void, Never>?
    private var searchGeneration: Int = 0

    init(dataSource: FileTreeDataSource) {
        self.dataSource = dataSource
    }

    /// Sets the search query and debounces the search
    func setSearchQuery(_ value: String) {
        guard let dataSource = dataSource else { return }

        // Cancel previous search
        pendingSearchTask?.cancel()

        // Debounce search
        pendingSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            guard !Task.isCancelled else { return }

            searchGeneration += 1
            let currentGeneration = searchGeneration

            await MainActor.run {
                dataSource.setSearchQuery(value)
            }
        }
    }

    /// Cancels any pending search
    func cancelSearch() {
        pendingSearchTask?.cancel()
        pendingSearchTask = nil
    }

    /// Gets the current search generation
    var currentSearchGeneration: Int {
        return searchGeneration
    }
}
