import SwiftUI

struct ToolExecutionTimelineView: View {
    let messages: [ChatMessage]

    @State private var expandedToolCallIds: Set<String> = []

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    private struct ToolEntry: Identifiable {
        let id: String
        let toolName: String
        let target: String?
        let status: ToolExecutionStatus?
        let content: String
        let timestamp: Date
    }

    private var entries: [ToolEntry] {
        let toolMessages = messages.filter { $0.isToolExecution }

        var byToolCallId: [String: ChatMessage] = [:]
        for message in toolMessages {
            guard let toolCallId = message.toolCallId, !toolCallId.isEmpty else { continue }
            if let existing = byToolCallId[toolCallId] {
                if message.timestamp >= existing.timestamp {
                    byToolCallId[toolCallId] = message
                }
            } else {
                byToolCallId[toolCallId] = message
            }
        }

        return byToolCallId
            .sorted { $0.value.timestamp < $1.value.timestamp }
            .map { (toolCallId, message) in
                let envelope = ToolExecutionEnvelope.decode(from: message.content)
                let payload = envelope?.payload?.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = envelope?.message ?? message.content
                let renderedContent = (payload?.isEmpty == false) ? payload! : fallback

                return ToolEntry(
                    id: toolCallId,
                    toolName: message.toolName ?? envelope?.toolName ?? localized("tool.default_name"),
                    target: message.targetFile ?? envelope?.targetFile,
                    status: message.toolStatus ?? envelope?.status,
                    content: renderedContent,
                    timestamp: message.timestamp
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Text(localized("tool_timeline.empty.title"))
                        .font(.headline)
                    Text(localized("tool_timeline.empty.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            statusIcon(for: entry.status)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.toolName)
                                    .font(.body.weight(.medium))

                                if let target = entry.target, !target.isEmpty {
                                    Text(target)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }

                            Spacer()

                            Button {
                                toggleExpanded(toolCallId: entry.id)
                            } label: {
                                Image(systemName: expandedToolCallIds.contains(entry.id) ?
                                        "chevron.up" : "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if expandedToolCallIds.contains(entry.id) {
                            Text(entry.content)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
    }

    private func toggleExpanded(toolCallId: String) {
        if expandedToolCallIds.contains(toolCallId) {
            expandedToolCallIds.remove(toolCallId)
        } else {
            expandedToolCallIds.insert(toolCallId)
        }
    }

    @ViewBuilder
    private func statusIcon(for status: ToolExecutionStatus?) -> some View {
        switch status {
        case .executing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .none:
            Image(systemName: "gear")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
