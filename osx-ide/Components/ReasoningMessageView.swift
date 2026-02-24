//
//  ReasoningMessageView.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import Foundation

/// View for displaying collapsible reasoning content
struct ReasoningMessageView: View {
    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    @Binding var isReasoningHidden: Bool
    @State private var showFullReasoning = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MarkdownMessageView(
                    content: message.content,
                    fontSize: fontSize,
                    fontFamily: fontFamily
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .foregroundColor(.primary)
                .cornerRadius(16)
                .textSelection(.enabled)
            }

            reasoningToggleButton

            if !isReasoningHidden {
                reasoningContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.06))
        .cornerRadius(14)
    }

    // MARK: - Private Components

    private var reasoningToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isReasoningHidden.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(localized("reasoning.title"))
                    .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isReasoningHidden ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var reasoningContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let text = (message.reasoning ?? "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if showFullReasoning || text.count <= 300 {
                Text(text)
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(String(text.prefix(300)) + "…")
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(showFullReasoning ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFullReasoning.toggle()
                    }
                }
                .font(.system(size: CGFloat(max(9, fontSize - 3))))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
    }
}
