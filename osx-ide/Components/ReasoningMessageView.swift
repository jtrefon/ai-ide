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
    let reasoning: String
    var fontSize: Double
    @Binding var isReasoningHidden: Bool
    @State private var showFullReasoning = false

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            reasoningToggleButton

            if !isReasoningHidden {
                reasoningContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(localized("reasoning.title"))
                    .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isReasoningHidden ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var reasoningContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let text = ChatPromptBuilder.reasoningForDisplay(reasoning)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if showFullReasoning || text.count <= 300 {
                Text(text)
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(String(text.prefix(300)) + "…")
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(showFullReasoning ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showFullReasoning.toggle()
                    }
                }
                .font(.system(size: CGFloat(max(9, fontSize - 3))))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}
