//
//  ToolCallsSummaryView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/06/2026.
//

import SwiftUI

struct ToolCallsSummaryView: View {
    let toolCalls: [AIToolCall]
    var fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(toolCalls, id: \.id) { call in
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(call.name)
                        .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                        .foregroundStyle(.primary)

                    if !call.arguments.isEmpty {
                        Text(formatArguments(call.arguments))
                            .font(.system(size: CGFloat(max(9, fontSize - 3)), design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
        }
    }

    private func formatArguments(_ args: [String: Any]) -> String {
        let sorted = args.sorted { $0.key < $1.key }
        let parts = sorted.prefix(3).map { "\($0.key): \($0.value)" }
        let summary = parts.joined(separator: ", ")
        if sorted.count > 3 {
            return summary + " …"
        }
        return summary
    }
}
