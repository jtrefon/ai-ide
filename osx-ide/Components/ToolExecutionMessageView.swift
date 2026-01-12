//
//  ToolExecutionMessageView.swift
//  osx-ide
//
//  Created by AI Assistant on 12/01/2026.
//

import SwiftUI
import Foundation
import AppKit

/// View for displaying tool execution messages with status and progress
struct ToolExecutionMessageView: View {
    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    
    @State private var isExpanded = false
    
    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (Always Visible)
            toolExecutionHeader
            
            // Content (Expandable)
            if isExpanded || message.toolStatus == .executing {
                toolExecutionContent
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Private Components
    
    private var toolExecutionHeader: some View {
        HStack(spacing: 6) {
            statusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.toolName ?? localized("tool.default_name"))
                    .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                    .foregroundColor(.primary)

                if let file = message.targetFile {
                    Text(file)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if message.toolStatus == .executing {
                    let trimmed = message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let lastLine = trimmed.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) ?? trimmed
                        Text(lastLine)
                            .font(.system(size: CGFloat(max(9, fontSize - 4))))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            
            Spacer()
            
            // Expand/Collapse button
            if message.toolStatus != .executing && !message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private var toolExecutionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.toolStatus == .executing {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
            }
            
            let content = message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !content.isEmpty {
                ScrollView {
                    Text(content)
                        .font(.system(size: CGFloat(max(10, fontSize - 2)), design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
    
    private var statusIcon: some View {
        Group {
            switch message.toolStatus {
            case .some(.executing):
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
            case .some(.completed):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            case .some(.failed):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 14))
            case .none:
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
            }
        }
        .frame(width: 16, height: 16)
    }
}
