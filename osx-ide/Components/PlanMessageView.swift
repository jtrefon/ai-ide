import SwiftUI

struct PlanMessageView: View {
    let content: String
    var fontSize: Double
    var fontFamily: String

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(title)
                        .font(.system(size: CGFloat(max(10, fontSize - 1)), weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                PlanOutlineView(rawPlan: content, fontSize: fontSize, fontFamily: fontFamily)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(14)
    }

    private var title: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("# strategic plan") { return "Strategic Plan" }
        if trimmed.hasPrefix("## tactical plan") { return "Tactical Plan" }
        if trimmed.hasPrefix("# tactical plan") { return "Tactical Plan" }
        return "Plan"
    }
}
