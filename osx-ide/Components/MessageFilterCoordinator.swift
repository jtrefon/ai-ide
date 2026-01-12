//
//  MessageFilterCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation

/// Coordinates message filtering logic for display
struct MessageFilterCoordinator {

    // MARK: - Public Methods

    /// Filters messages to display, removing empty assistant messages
    func filterMessages(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            if message.role == .assistant && isEmptyAssistantMessage(message) {
                return false
            }
            return true
        }
    }

    /// Determines if a message should be displayed in the list
    func shouldDisplayMessage(_ message: ChatMessage, in messages: [ChatMessage]) -> Bool {
        if isEmptyAssistantMessage(message) {
            return false
        }

        if message.isToolExecution {
            return shouldDisplayToolExecutionMessage(message, in: messages)
        }

        return true
    }

    // MARK: - Private Methods

    private func isEmptyAssistantMessage(_ message: ChatMessage) -> Bool {
        message.role == .assistant &&
        message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (message.toolCalls?.isEmpty ?? true)
    }

    private func shouldDisplayToolExecutionMessage(_ message: ChatMessage, in messages: [ChatMessage]) -> Bool {
        guard let toolCallId = message.toolCallId else {
            return true
        }

        guard let latestForId = messages.last(where: { $0.toolCallId == toolCallId }) else {
            return true
        }

        return message.id == latestForId.id
    }
}
