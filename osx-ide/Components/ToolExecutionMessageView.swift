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

    @ObservedObject private var timeoutCenter = ToolTimeoutCenter.shared

    @State private var isExpanded = false

    private var envelope: ToolExecutionEnvelope? {
        ToolExecutionEnvelope.decode(from: message.content)
    }

    private var displayToolName: String {
        message.toolName ?? envelope?.toolName ?? localized("tool.default_name")
    }

    private var displayTargetFile: String? {
        message.targetFile ?? envelope?.targetFile
    }

    private var displayStatus: ToolExecutionStatus? {
        message.toolStatus ?? envelope?.status
    }

    private var displayPayload: String {
        let directContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let envelope else { return directContent }

        if let payload = envelope.payload?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty {
            return payload
        }
        return envelope.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewContent: String? {
        guard let preview = envelope?.preview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty else {
            return nil
        }
        return preview
    }

    private var isCommandTool: Bool {
        displayToolName == "run_command"
    }

    private var isFileMutationTool: Bool {
        ["write_file", "create_file", "replace_in_file", "delete_file"].contains(displayToolName)
    }

    private var isReadFileTool: Bool {
        displayToolName == "read_file"
    }

    private var readFileRangeLabel: String? {
        guard let previewContent else { return nil }
        let lines = previewContent.split(separator: "\n").map(String.init)
        return lines.first(where: { $0.hasPrefix("Lines:") || $0.hasPrefix("From line:") })
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (Always Visible)
            toolExecutionHeader

            // Content (Expandable)
            if isExpanded || displayStatus == .executing {
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
                Text(displayToolName)
                    .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                    .foregroundColor(.primary)

                if let file = displayTargetFile {
                    Text(file)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if isReadFileTool, let readFileRangeLabel {
                    Text(readFileRangeLabel)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                }

                if displayStatus == .executing {
                    let trimmed = displayPayload.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let lastLine = trimmed.split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        ).last.map(String.init) ?? trimmed
                        Text(lastLine)
                            .font(.system(size: CGFloat(max(9, fontSize - 4))))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }

            Spacer()

            if displayStatus == .executing,
               let toolCallId = message.toolCallId,
               timeoutCenter.activeToolCallId == toolCallId {
                HStack(spacing: 6) {
                    if let seconds = timeoutCenter.countdownSeconds {
                        Text("\(seconds)s")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }

                    Button {
                        timeoutCenter.cancelActiveToolNow()
                    } label: {
                        Image(systemName: "xmark.octagon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Kill tool")

                    Button {
                        timeoutCenter.togglePause()
                    } label: {
                        Image(systemName: timeoutCenter.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(timeoutCenter.isPaused ? "Resume timeout" : "Pause timeout")
                }
            }

            // Expand/Collapse button
            if displayStatus != .executing &&
                !displayPayload.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
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
            if displayStatus == .executing {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 16, height: 16)
            }

            if let previewContent {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.system(size: CGFloat(max(9, fontSize - 4)), weight: .semibold))
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(previewContent)
                            .font(.system(size: CGFloat(max(10, fontSize - 2)), design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
            }

            let content = displayPayload.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !content.isEmpty {
                if isCommandTool {
                    commandPreview(content)
                } else if isReadFileTool {
                    readFilePreview(content)
                } else if isFileMutationTool {
                    fileMutationPreview(content)
                } else {
                    genericPayloadPreview(content)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func genericPayloadPreview(_ content: String) -> some View {
        ScrollView {
            Text(content)
                .font(.system(size: CGFloat(max(10, fontSize - 2)), design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 220)
    }

    private func fileMutationPreview(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(fileOperationLabel)
                    .font(.system(size: CGFloat(max(9, fontSize - 4)), weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)

                if let target = displayTargetFile {
                    Text(target)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            genericPayloadPreview(content)
        }
    }

    private func readFilePreview(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Read")
                    .font(.system(size: CGFloat(max(9, fontSize - 4)), weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)

                if let target = displayTargetFile {
                    Text(target)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let readFileRangeLabel {
                Text(readFileRangeLabel)
                    .font(.system(size: CGFloat(max(9, fontSize - 4))))
                    .foregroundColor(.secondary)
            }

            genericPayloadPreview(content)
        }
    }

    private func commandPreview(_ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("CLI")
                    .font(.system(size: CGFloat(max(9, fontSize - 4)), weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                if let status = displayStatus {
                    Text(status.rawValue.capitalized)
                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                        .foregroundColor(.secondary)
                }
            }

            genericPayloadPreview(content)
        }
    }

    private var fileOperationLabel: String {
        switch displayToolName {
        case "write_file":
            return "Write"
        case "create_file":
            return "Create"
        case "replace_in_file":
            return "Edit"
        case "delete_file":
            return "Delete"
        default:
            return "File"
        }
    }

    private var statusIcon: some View {
        Group {
            switch displayStatus {
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
