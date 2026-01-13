//
//  MessageListView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Foundation

fileprivate func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct MessageListView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    @State private var hiddenReasoningMessageIds: Set<UUID> = []

    private let filterCoordinator = MessageFilterCoordinator()

    private func scrollToBottom(proxy: ScrollViewProxy) {
        Task { @MainActor in
            proxy.scrollTo("__bottom__", anchor: .bottom)
        }
    }

    private func reasoningHiddenBinding(for messageId: UUID) -> Binding<Bool> {
        Binding(
            get: { hiddenReasoningMessageIds.contains(messageId) },
            set: { isHidden in
                if isHidden {
                    hiddenReasoningMessageIds.insert(messageId)
                } else {
                    hiddenReasoningMessageIds.remove(messageId)
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        if filterCoordinator.shouldDisplayMessage(message, in: messages) {
                            MessageView(
                                message: message,
                                fontSize: fontSize,
                                fontFamily: fontFamily,
                                isReasoningHidden: reasoningHiddenBinding(for: message.id)
                            )
                            .id(message.id)
                        }
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
            .onChange(of: messages.last?.id) { _ in
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

    init(message: ChatMessage, fontSize: Double, fontFamily: String, isReasoningHidden: Binding<Bool>) {
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
        Text(message.role == .user ? localized("chat.role.you") : localized("chat.role.assistant"))
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

struct MessageListView_Previews: PreviewProvider {
    static var previews: some View {
        MessageListView(
            messages: [
                ChatMessage(role: .assistant, content: "Hello! How can I help you today?"),
                ChatMessage(role: .user, content: "Can you explain this code?"),
                ChatMessage(role: .assistant, content: "Sure! This code implements a chat interface."),
            ],
            isSending: true,
            fontSize: 12,
            fontFamily: "Menlo"
        )
    }
}