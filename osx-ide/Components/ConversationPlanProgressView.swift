import SwiftUI
import Foundation

struct ConversationPlanProgressView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double

    @State private var isExpanded: Bool = true

    private var latestPlanMessage: ChatMessage? {
        messages.last(where: { message in
            message.role == .assistant && isPlanContent(message.content)
        })
    }

    private var hasContent: Bool {
        latestPlanMessage != nil || isSending
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Plan & Progress")
                        .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    Button(isExpanded ? "Hide" : "Show") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: CGFloat(max(9, fontSize - 4))))
                    .foregroundColor(.secondary)
                }

                if isExpanded {
                    if let plan = latestPlanMessage {
                        PlanOutlineView(rawPlan: plan.content, fontSize: fontSize, fontFamily: "")
                    } else if isSending {
                        Text("Preparing plan…")
                            .font(.system(size: CGFloat(max(9, fontSize - 3))))
                            .foregroundColor(.secondary)
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

    private func isPlanContent(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("# strategic plan") ||
            trimmed.hasPrefix("## tactical plan") ||
            trimmed.hasPrefix("# tactical plan")
    }
}
