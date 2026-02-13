import SwiftUI
import Foundation

struct ActivityFeedView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double

    @State private var isExpanded: Bool = true

    var body: some View {
        let feedItems = recentItems
        if !feedItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Activity")
                        .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Button(isExpanded ? "Hide" : "Show") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: CGFloat(max(9, fontSize - 4))))
                    .foregroundColor(.secondary)
                }

                if isExpanded {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(feedItems) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.system(size: CGFloat(max(9, fontSize - 4))))
                                    .foregroundColor(item.tint)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: CGFloat(max(10, fontSize - 3)), weight: .medium))
                                        .lineLimit(1)

                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: CGFloat(max(9, fontSize - 4))))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }

                                Spacer(minLength: 0)

                                Text(relativeTimeString(for: item.timestamp))
                                    .font(.system(size: CGFloat(max(8, fontSize - 5))))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.18)),
                alignment: .bottom
            )
        }
    }

    private var recentItems: [FeedItem] {
        var items: [FeedItem] = []

        if isSending {
            items.append(FeedItem(
                title: "Thinking through the request",
                detail: "Preparing the next response",
                icon: "brain.head.profile",
                tint: .blue,
                timestamp: Date()
            ))
        }

        for message in messages.suffix(30).reversed() {
            if message.isToolExecution {
                items.append(feedItem(forToolMessage: message))
            } else if isPlanMessage(message) {
                items.append(FeedItem(
                    title: message.content.lowercased().contains("tactical") ? "Tactical plan updated" : "Strategic plan updated",
                    detail: firstNonEmptyLine(in: message.content),
                    icon: "list.bullet.rectangle",
                    tint: .purple,
                    timestamp: message.timestamp
                ))
            } else if hasReasoning(message) {
                items.append(FeedItem(
                    title: "Reasoning captured",
                    detail: "Model included internal reasoning notes",
                    icon: "lightbulb",
                    tint: .yellow,
                    timestamp: message.timestamp
                ))
            }

            if items.count >= 6 {
                break
            }
        }

        return items
    }

    private func feedItem(forToolMessage message: ChatMessage) -> FeedItem {
        let envelope = ToolExecutionEnvelope.decode(from: message.content)
        let status = envelope?.status ?? message.toolStatus
        let toolName = envelope?.toolName ?? message.toolName ?? "tool"
        let title: String
        let icon: String
        let tint: Color

        switch status {
        case .completed:
            title = "Completed: \(toolName)"
            icon = "checkmark.circle.fill"
            tint = .green
        case .failed:
            title = "Failed: \(toolName)"
            icon = "xmark.circle.fill"
            tint = .red
        default:
            title = "Running: \(toolName)"
            icon = "hourglass"
            tint = .orange
        }

        let detail = envelope?.targetFile ?? message.targetFile ?? firstNonEmptyLine(in: envelope?.preview ?? message.content)

        return FeedItem(
            title: title,
            detail: detail,
            icon: icon,
            tint: tint,
            timestamp: message.timestamp
        )
    }

    private func firstNonEmptyLine(in text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        return trimmed
    }

    private func hasReasoning(_ message: ChatMessage) -> Bool {
        guard let reasoning = message.reasoning else { return false }
        return !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isPlanMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("# strategic plan") ||
            trimmed.hasPrefix("## tactical plan") ||
            trimmed.hasPrefix("# tactical plan")
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct FeedItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
    let icon: String
    let tint: Color
    let timestamp: Date
}
