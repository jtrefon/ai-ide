import Foundation
import SwiftUI

@MainActor
final class WorkspaceLifecycleCoordinator {
    private let conversationManager: ConversationManagerProtocol
    private let configureCodebaseIndex: (URL) -> Void
    private let loadProjectSession: (URL) async -> Void

    init(
        conversationManager: ConversationManagerProtocol,
        configureCodebaseIndex: @escaping (URL) -> Void,
        loadProjectSession: @escaping (URL) async -> Void
    ) {
        self.conversationManager = conversationManager
        self.configureCodebaseIndex = configureCodebaseIndex
        self.loadProjectSession = loadProjectSession
    }

    func workspaceRootDidChange(to newRoot: URL) {
        conversationManager.updateProjectRoot(newRoot)
        configureCodebaseIndex(newRoot)

        Task { [loadProjectSession] in
            await loadProjectSession(newRoot)
        }
    }
}
