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
            } else if isPlanMessage {
                PlanMessageView(
                    content: message.content,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
            } else if hasReasoning {
                ReasoningMessageView(
                    message: message,
                    fontSize: fontSize,
                    fontFamily: fontFamily,
                    isReasoningHidden: $isReasoningHidden
                )
            } else if message.role == .assistant {
                MarkdownMessageView(
                    content: message.content,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor(for: message))
                .foregroundColor(foregroundColor(for: message))
                .cornerRadius(16)
                .textSelection(.enabled)
                .contextMenu {
                    copyMessageButton
                }
            } else {
                Text(message.content)
                    .font(.system(size: CGFloat(fontSize)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor(for: message))
                    .foregroundColor(foregroundColor(for: message))
                    .cornerRadius(16)
                    .textSelection(.enabled)
                    .contextMenu {
                        copyMessageButton
                    }
            }
        }
    }

    // MARK: - Private Methods

    private func backgroundColor(for message: ChatMessage) -> Color {
        if message.role == .user {
            return Color.accentColor.opacity(0.8)
        }

        return Color(NSColor.controlBackgroundColor)
    }

    private func foregroundColor(for message: ChatMessage) -> Color {
        if message.role == .user {
            return Color.white
        }

        return Color.primary
    }

    private var hasReasoning: Bool {
        guard let reasoning = message.reasoning else { return false }
        return !reasoning.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
    }

    private var isPlanMessage: Bool {
        guard message.role == .assistant else { return false }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("# strategic plan") ||
            trimmed.hasPrefix("## tactical plan") ||
            trimmed.hasPrefix("# tactical plan")
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
