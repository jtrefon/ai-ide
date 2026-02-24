//
//  MessageListView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import Foundation
import SwiftUI

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct MessageListView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    @State private var expandedReasoningMessageIds: Set<UUID> = []

    private let filterCoordinator = MessageFilterCoordinator()

    private var visibleMessages: [ChatMessage] {
        messages.filter { filterCoordinator.shouldDisplayMessage($0, in: messages) }
    }

    private var visibleMessagesSignature: String {
        "\(visibleMessages.count):"
            + visibleMessages
            .suffix(20)
            .map { message in
                [
                    message.id.uuidString,
                    message.role.rawValue,
                    message.toolStatus?.rawValue ?? "",
                    message.toolCallId ?? "",
                    String(message.content.count),
                    String(message.reasoning?.count ?? 0),
                ].joined(separator: "|")
            }
            .joined(separator: "~")
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
        }
    }

    private func reasoningHiddenBinding(for messageId: UUID) -> Binding<Bool> {
        Binding(
            get: { !expandedReasoningMessageIds.contains(messageId) },
            set: { isHidden in
                if isHidden {
                    expandedReasoningMessageIds.remove(messageId)
                } else {
                    expandedReasoningMessageIds.insert(messageId)
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleMessages) { message in
                        MessageView(
                            message: message,
                            fontSize: fontSize,
                            fontFamily: fontFamily,
                            isReasoningHidden: reasoningHiddenBinding(for: message.id)
                        )
                        .id(message.id)
                    }

                    if isSending {
                        typingIndicator
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("__bottom__")
                }
                .padding()
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: visibleMessagesSignature) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isSending) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    // MARK: - Private Components

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(localized("chat.typing"))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.15))
        .cornerRadius(16)
        .frame(maxWidth: 400)
    }
}

struct MessageView: View {
    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    @Binding var isReasoningHidden: Bool

    private let contentCoordinator: MessageContentCoordinator

    init(
        message: ChatMessage, fontSize: Double, fontFamily: String, isReasoningHidden: Binding<Bool>
    ) {
        self.message = message
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self._isReasoningHidden = isReasoningHidden
        self.contentCoordinator = MessageContentCoordinator(
            message: message,
            fontSize: fontSize,
            fontFamily: fontFamily,
            isReasoningHidden: isReasoningHidden
        )
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                roleLabel
                contentCoordinator.makeMessageContent()

                if let codeContext = message.codeContext {
                    CodePreviewView(
                        code: codeContext,
                        fontSize: fontSize,
                        fontFamily: fontFamily
                    )
                }
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    // MARK: - Private Components

    private var roleLabel: some View {
        Text(roleLabelText)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var roleLabelText: String {
        switch message.role {
        case .user:
            return localized("chat.role.you")
        case .assistant:
            return localized("chat.role.assistant")
        case .tool:
            return "Tool"
        case .system:
            return "System"
        }
    }
}

struct MessageListView_Previews: PreviewProvider {
    static var previews: some View {
        MessageListView(
            messages: [
                ChatMessage(role: .assistant, content: "Hello! How can I help you today?"),
                ChatMessage(role: .user, content: "Can you explain this code?"),
                ChatMessage(
                    role: .assistant, content: "Sure! This code implements a chat interface."),
            ],
            isSending: true,
            fontSize: 12,
            fontFamily: "Menlo"
        )
    }
}
