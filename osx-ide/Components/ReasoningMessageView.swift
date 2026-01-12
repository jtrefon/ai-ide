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
            // Reasoning toggle button
            reasoningToggleButton
            
            // Reasoning content (when not hidden)
            if !isReasoningHidden {
                reasoningContent
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.12))
        .cornerRadius(14)
        .frame(maxWidth: 400)
    }
    
    // MARK: - Private Components
    
    private var reasoningToggleButton: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isReasoningHidden.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isReasoningHidden ? "eye.slash" : "eye")
                        .font(.system(size: 10, weight: .medium))
                    
                    Text(localized("reasoning.title"))
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            
            if !isReasoningHidden {
                Spacer()
                
                Button(showFullReasoning ? localized("common.less") : localized("common.more")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullReasoning.toggle()
                    }
                }
                .buttonStyle(.borderless)

                Button(localized("common.hide")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isReasoningHidden = true
                    }
                }
                .buttonStyle(.borderless)

                Spacer()
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }
    
    private var reasoningContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let reasoningContent = (message.reasoning ?? "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if showFullReasoning {
                Text(reasoningContent)
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let preview = String(reasoningContent.prefix(200))
                Text(preview + (reasoningContent.count > 200 ? "..." : ""))
                    .font(.system(size: CGFloat(max(10, fontSize - 2))))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
