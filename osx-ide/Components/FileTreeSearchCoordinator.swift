//
//  FileTreeSearchCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 11/01/2026.
//

import Foundation

/// Handles search functionality for the file tree
@MainActor
final class FileTreeSearchCoordinator {
    private let dataSource: FileTreeDataSource
    private var pendingSearchTask: Task<Void, Never>?

    init(dataSource: FileTreeDataSource) {
        self.dataSource = dataSource
    }

    /// Sets the search query and debounces the search
    func setSearchQuery(_ value: String) {
        // Cancel previous search
        pendingSearchTask?.cancel()

        // Debounce search
        pendingSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s debounce
            guard !Task.isCancelled else { return }

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
}
