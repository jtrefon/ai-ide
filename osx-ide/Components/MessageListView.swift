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

private struct TypingDotsBubbleView: View {
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(dotOpacity(for: index, time: time))
                        .scaleEffect(dotScale(for: index, time: time))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(NSColor.quaternaryLabelColor).opacity(0.2))
            .clipShape(Capsule())
            .frame(height: 34)
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isActive ? 1 : 0.95, anchor: .leading)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isActive)
        }
    }

    private func dotOpacity(for index: Int, time: TimeInterval) -> Double {
        guard isActive else { return 0.18 }
        let wave = (sin((time * 4.4) - (Double(index) * 0.6)) + 1) / 2
        return 0.3 + (wave * 0.7)
    }

    private func dotScale(for index: Int, time: TimeInterval) -> CGFloat {
        guard isActive else { return 0.8 }
        let wave = (sin((time * 4.4) - (Double(index) * 0.6)) + 1) / 2
        return 0.8 + CGFloat(wave * 0.35)
    }
}

struct MessageListView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    @State private var expandedReasoningMessageIds: Set<UUID> = []

    private let filterCoordinator = MessageFilterCoordinator()

    private var orderedMessages: [ChatMessage] {
        messages
    }

    private var visibleMessages: [ChatMessage] {
        orderedMessages.filter { filterCoordinator.shouldDisplayMessage($0, in: orderedMessages) }
    }

    private var visibleMessageIDsSignature: String {
        visibleMessages.suffix(40).map(\.id.uuidString).joined(separator: "~")
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
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
        GeometryReader { geometry in
            let maxBubbleWidth = min(680, max(260, geometry.size.width * 0.72))

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleMessages) { message in
                            MessageView(
                                message: message,
                                fontSize: fontSize,
                                fontFamily: fontFamily,
                                maxBubbleWidth: maxBubbleWidth,
                                isReasoningHidden: reasoningHiddenBinding(for: message.id)
                            )
                            .id(message.id)
                            .transition(
                                AnyTransition.asymmetric(
                                    insertion: AnyTransition.opacity
                                        .combined(with: AnyTransition.offset(y: 10))
                                        .combined(with: AnyTransition.scale(scale: 0.98)),
                                    removal: AnyTransition.opacity
                                )
                            )
                        }

                        typingIndicator(maxBubbleWidth: maxBubbleWidth)

                        Color.clear
                            .frame(height: 1)
                            .id("__bottom__")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: visibleMessageIDsSignature) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isSending) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Private Components

    private func typingIndicator(maxBubbleWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            TypingDotsBubbleView(isActive: isSending)
                .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            Spacer()
        }
        .frame(height: 34)
        .accessibilityHidden(!isSending)
    }
}

struct MessageView: View {
    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    var maxBubbleWidth: CGFloat
    @Binding var isReasoningHidden: Bool

    private let contentCoordinator: MessageContentCoordinator

    init(
        message: ChatMessage,
        fontSize: Double,
        fontFamily: String,
        maxBubbleWidth: CGFloat,
        isReasoningHidden: Binding<Bool>
    ) {
        self.message = message
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.maxBubbleWidth = maxBubbleWidth
        self._isReasoningHidden = isReasoningHidden
        self.contentCoordinator = MessageContentCoordinator(
            message: message,
            fontSize: fontSize,
            fontFamily: fontFamily,
            isReasoningHidden: isReasoningHidden
        )
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
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
            .frame(maxWidth: maxBubbleWidth, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    // MARK: - Private Components

    private var roleLabel: some View {
        Text(roleLabelText)
            .font(.caption2)
            .foregroundColor(.secondary)
            .monospacedDigit()
    }

    private var roleLabelText: String {
        message.timestamp.formatted(date: .omitted, time: .standard)
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
