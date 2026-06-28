//
//  MessageContentCoordinator.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import Foundation
import AppKit

/// Coordinates message content rendering and styling
@MainActor
struct MessageContentCoordinator {

    // MARK: - Properties

    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    @Binding var isReasoningHidden: Bool

    // MARK: - Initialization

    init(message: ChatMessage, fontSize: Double, fontFamily: String, isReasoningHidden: Binding<Bool>) {
        self.message = message
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self._isReasoningHidden = isReasoningHidden
    }

    // MARK: - Public Methods

    /// Creates the appropriate message content view based on message type
    func makeMessageContent() -> some View {
        Group {
            if message.isToolExecution {
                ToolExecutionMessageView(
                    message: message,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
            } else if isReasoningOutcomeMessage {
                ReasoningOutcomeMessageView(
                    message: message,
                    fontSize: fontSize
                )
            } else {
                assistantMessageContent
            }
        }
    }

    private var assistantMessageContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if hasReasoning {
                ReasoningMessageView(
                    reasoning: message.reasoning ?? "",
                    fontSize: fontSize,
                    isReasoningHidden: $isReasoningHidden
                )
            }

            if hasVisibleContent {
                MarkdownMessageView(
                    content: visibleContent,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground(for: message))
                .foregroundColor(bubbleForegroundColor(for: message))
                .cornerRadius(12, corners: bubbleCorners(for: message))
                .textSelection(.enabled)
                .contextMenu {
                    copyMessageButton
                }
            }

            if hasToolCalls {
                ToolCallsSummaryView(
                    toolCalls: message.toolCalls ?? [],
                    fontSize: fontSize
                )
            }
        }
    }

    // MARK: - Private Methods

    private func bubbleBackground(for message: ChatMessage) -> Color {
        if message.role == .user {
            return Color.accentColor
        }

        return Color(nsColor: .secondarySystemFill)
    }

    private func bubbleForegroundColor(for message: ChatMessage) -> Color {
        if message.role == .user {
            return Color.white
        }

        return Color.primary
    }

    private func bubbleCorners(for message: ChatMessage) -> MessageUIComponents.RectCorner {
        if message.role == .user {
            return [.topLeft, .topRight, .bottomLeft]
        }

        return [.topLeft, .topRight, .bottomRight]
    }

    private var hasReasoning: Bool {
        guard let reasoning = message.reasoning else { return false }
        return !reasoning.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    private var hasToolCalls: Bool {
        !(message.toolCalls?.isEmpty ?? true)
    }

    private var hasVisibleContent: Bool {
        !visibleContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleContent: String {
        let split = ChatPromptBuilder.splitReasoning(from: message.content)
        return split.content
    }

    private var isReasoningOutcomeMessage: Bool {
        message.role == .system && ReasoningOutcomeMessageView.parse(from: message.content) != nil
    }

    private var copyMessageButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
        } label: {
            Text(localized("chat.copy_message"))
            Image(systemName: "doc.on.doc")
        }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
