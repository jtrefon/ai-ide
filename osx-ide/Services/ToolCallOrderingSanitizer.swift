//
//  ToolCallOrderingSanitizer.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import Foundation

/// Sanitizes tool call ordering in chat messages to ensure proper conversation flow
struct ToolCallOrderingSanitizer {

    // MARK: - Nested Types

    private struct ToolCallOrderingBlock {
        let startIndexInOutput: Int
        let toolCallIds: Set<String>
    }

    // MARK: - Properties

    private var output: [ChatMessage] = []
    private var pending: ToolCallOrderingBlock?
    private var remainingToolCallIds: Set<String> = []

    // MARK: - Public Methods

    /// Sanitizes a list of chat messages to ensure proper tool call ordering
    func sanitize(_ messages: [ChatMessage]) -> [ChatMessage] {
        var sanitizer = ToolCallOrderingSanitizer()
        return sanitizer.sanitizeInternal(messages)
    }

    // MARK: - Private Methods

    private mutating func sanitizeInternal(_ messages: [ChatMessage]) -> [ChatMessage] {
        if messages.isEmpty { return [] }
        output = []
        output.reserveCapacity(messages.count)

        for msg in messages {
            handleMessage(msg)
        }

        if hasPendingResponses {
            dropPendingBlock()
        }
        return output
    }

    private var hasPendingResponses: Bool {
        pending != nil && !remainingToolCallIds.isEmpty
    }

    private mutating func handleMessage(_ msg: ChatMessage) {
        if msg.role == .assistant {
            if hasPendingResponses { dropPendingBlock() }
            startPendingBlock(from: msg)
            return
        }

        if msg.role == .tool {
            acceptToolMessageIfValid(msg)
            return
        }

        if hasPendingResponses { dropPendingBlock() }
        output.append(msg)
    }

    private mutating func dropPendingBlock() {
        guard let pendingBlock = pending else { return }
        if pendingBlock.startIndexInOutput < output.count {
            output.removeSubrange(pendingBlock.startIndexInOutput..<output.count)
        }
        pending = nil
        remainingToolCallIds.removeAll()
    }

    private mutating func startPendingBlock(from assistant: ChatMessage) {
        guard let calls = assistant.toolCalls, !calls.isEmpty else {
            output.append(assistant)
            return
        }
        let ids = Set(calls.map { $0.id })
        let start = output.count
        output.append(assistant)
        pending = ToolCallOrderingBlock(startIndexInOutput: start, toolCallIds: ids)
        remainingToolCallIds = ids
    }

    private mutating func acceptToolMessageIfValid(_ toolMessage: ChatMessage) {
        if toolMessage.toolStatus == .executing { return }
        guard let toolCallId = toolMessage.toolCallId, !toolCallId.isEmpty else { return }
        guard let pendingBlock = pending else { return }
        guard pendingBlock.toolCallIds.contains(toolCallId) else { return }
        guard remainingToolCallIds.contains(toolCallId) else { return }

        output.append(toolMessage)
        remainingToolCallIds.remove(toolCallId)
        if remainingToolCallIds.isEmpty {
            pending = nil
        }
    }
}
