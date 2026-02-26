import SwiftUI
import Foundation

struct ConversationPlanProgressView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    let onStopGenerating: (() -> Void)?
    var fontSize: Double

    @State private var isExpanded: Bool = false

    private let maxExpandedPlanHeight: CGFloat = 280

    private var latestPlanMessage: ChatMessage? {
        messages.last(where: { message in
            message.role == .assistant && isPlanContent(message.content)
        })
    }

    private var hasContent: Bool {
        latestPlanMessage != nil || isSending
    }

    private var progress: PlanProgress {
        guard let plan = latestPlanMessage else { return PlanProgress(completed: 0, total: 0) }

        let checklistProgress = PlanChecklistTracker.progress(in: plan.content)
        if checklistProgress.total > 0 {
            return PlanProgress(completed: checklistProgress.completed, total: checklistProgress.total)
        }

        let stepCount = plan.content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard let first = line.first else { return false }
                return first.isNumber && line.contains(".")
            }
            .count
        return PlanProgress(completed: 0, total: stepCount)
    }

    private var activePlanItem: PlanActiveItem? {
        guard let plan = latestPlanMessage else { return nil }
        return PlanActiveItemResolver.activeItem(in: plan.content)
    }

    private var headerTitle: String {
        activePlanItem?.stepTitle ?? "Implementation Plan"
    }

    private var headerSubtitle: String? {
        activePlanItem?.substepTitle?.nilIfEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(headerTitle)
                                .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .semibold))
                                .foregroundColor(.primary)

                            if progress.total > 0 {
                                Text("\(progress.completed)/\(progress.total)")
                                    .font(.system(size: CGFloat(max(9, fontSize - 3)), weight: .medium).monospacedDigit())
                                    .foregroundColor(.secondary)

                                Text("\(progress.percentage)%")
                                    .font(.system(size: CGFloat(max(9, fontSize - 3)), weight: .semibold).monospacedDigit())
                                    .foregroundColor(progress.isComplete ? .green : .accentColor)
                            }
                        }

                        if let subtitle = headerSubtitle {
                            Text(subtitle)
                                .font(.system(size: CGFloat(max(9, fontSize - 3)), weight: .regular))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer()

                    if isSending {
                        ProgressView()
                            .scaleEffect(0.6)

                        if let onStopGenerating {
                            Button(action: onStopGenerating) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Stop model generation")
                            .accessibilityIdentifier("ConversationStopGenerationButton")
                        }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if progress.total > 0 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .tint(progress.isComplete ? .green : .accentColor)
                        .scaleEffect(y: 0.6)
                }

                if isExpanded {
                    if let plan = latestPlanMessage {
                        ScrollView(.vertical) {
                            PlanOutlineView(rawPlan: plan.content, fontSize: fontSize, fontFamily: "")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: maxExpandedPlanHeight)
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
        return trimmed.hasPrefix("# implementation plan")
    }
}

private struct PlanProgress {
    let completed: Int
    let total: Int
    var percentage: Int {
        guard total > 0 else { return 0 }
        return Int((Double(completed) / Double(total) * 100).rounded())
    }
    var isComplete: Bool { completed >= total && total > 0 }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
