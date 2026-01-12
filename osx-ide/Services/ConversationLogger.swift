//
//  ConversationLogger.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation

/// Handles logging for conversation-related events
@MainActor
struct ConversationLogger {

    // MARK: - Public Methods

    /// Logs a user message
    func logUserMessage(
        text: String,
        mode: String,
        projectRootPath: String,
        conversationId: String,
        hasSelectionContext: Bool
    ) {
        Task.detached(priority: .utility) {
            await AIToolTraceLogger.shared.log(
                type: "chat.user_message",
                data: [
                    "mode": mode,
                    "projectRoot": projectRootPath,
                    "inputLength": text.count,
                    "hasSelectionContext": hasSelectionContext,
                ]
            )

            await AppLogger.shared.info(
                category: .conversation, message: "chat.user_message",
                metadata: [
                    "conversationId": conversationId,
                    "mode": mode,
                    "projectRoot": projectRootPath,
                    "inputLength": text.count,
                    "hasSelectionContext": hasSelectionContext,
                ]
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.user_message",
                data: [
                    "content": text,
                    "hasSelectionContext": hasSelectionContext,
                ]
            )
        }
    }

    /// Logs an AI request start
    func logAIRequestStart(mode: String, historyCount: Int) {
        Task.detached(priority: .utility) {
            await AIToolTraceLogger.shared.log(
                type: "chat.ai_request_start",
                data: [
                    "mode": mode,
                    "historyCount": historyCount,
                ]
            )
        }
    }

    /// Logs a chat error
    func logChatError(
        conversationId: String,
        errorDescription: String
    ) {
        Task.detached(priority: .utility) {
            await AppLogger.shared.error(
                category: .error, message: "chat.error",
                metadata: [
                    "conversationId": conversationId,
                    "error": errorDescription,
                ]
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "chat.error",
                data: [
                    "error": errorDescription
                ]
            )
        }
    }

    /// Logs a conversation start
    func logConversationStart(
        conversationId: String,
        mode: String,
        projectRootPath: String,
        previousConversationId: String? = nil
    ) {
        Task.detached(priority: .utility) {
            var metadata: [String: Any] = [
                "conversationId": conversationId,
                "mode": mode,
                "projectRoot": projectRootPath,
            ]
            if let previousId = previousConversationId {
                metadata["previousConversationId"] = previousId
            }

            await AppLogger.shared.info(
                category: .conversation, message: "conversation.start",
                metadata: metadata
            )
            await ConversationLogStore.shared.append(
                conversationId: conversationId,
                type: "conversation.start",
                data: [
                    "mode": mode,
                    "projectRoot": projectRootPath,
                    "previousConversationId": previousConversationId as Any,
                ]
            )
            await ConversationIndexStore.shared.appendStart(
                conversationId: conversationId,
                mode: mode,
                projectRootPath: projectRootPath
            )
        }
    }

    /// Initializes logging stores for a project root
    func initializeProjectRoot(_ root: URL) {
        Task.detached(priority: .utility) {
            await AppLogger.shared.setProjectRoot(root)
            await CrashReporter.shared.setProjectRoot(root)
            await ConversationLogStore.shared.setProjectRoot(root)
            await ExecutionLogStore.shared.setProjectRoot(root)
            await ConversationIndexStore.shared.setProjectRoot(root)
            await ConversationPlanStore.shared.setProjectRoot(root)
            await PatchSetStore.shared.setProjectRoot(root)
            await CheckpointManager.shared.setProjectRoot(root)

            await AppLogger.shared.info(
                category: .app, message: "logging.project_root_set",
                metadata: [
                    "projectRoot": root.path
                ]
            )
        }
    }

    /// Logs trace start
    func logTraceStart(mode: String, projectRootPath: String, logPath: String) {
        Task.detached(priority: .utility) {
            await AIToolTraceLogger.shared.log(
                type: "trace.start",
                data: [
                    "logFile": logPath,
                    "mode": mode,
                    "projectRoot": projectRootPath,
                ]
            )
        }
    }
}
