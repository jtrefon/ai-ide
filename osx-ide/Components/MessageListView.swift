//
//  MessageListView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Foundation

struct RectCorner: OptionSet, Sendable {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomRight = RectCorner(rawValue: 1 << 2)
    static let bottomLeft = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let p1 = CGPoint(x: rect.minX, y: rect.minY)
        let p2 = CGPoint(x: rect.maxX, y: rect.minY)
        let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let p4 = CGPoint(x: rect.minX, y: rect.maxY)
        
        // Start from top-left
        if corners.contains(.topLeft) {
            path.move(to: CGPoint(x: p1.x + radius, y: p1.y))
        } else {
            path.move(to: p1)
        }
        
        // Top edge to top-right
        if corners.contains(.topRight) {
            path.addLine(to: CGPoint(x: p2.x - radius, y: p2.y))
            path.addArc(center: CGPoint(x: p2.x - radius, y: p2.y + radius), radius: radius, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        } else {
            path.addLine(to: p2)
        }
        
        // Right edge to bottom-right
        if corners.contains(.bottomRight) {
            path.addLine(to: CGPoint(x: p3.x, y: p3.y - radius))
            path.addArc(center: CGPoint(x: p3.x - radius, y: p3.y - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        } else {
            path.addLine(to: p3)
        }
        
        // Bottom edge to bottom-left
        if corners.contains(.bottomLeft) {
            path.addLine(to: CGPoint(x: p4.x + radius, y: p4.y))
            path.addArc(center: CGPoint(x: p4.x + radius, y: p4.y - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        } else {
            path.addLine(to: p4)
        }
        
        // Left edge to top-left
        if corners.contains(.topLeft) {
            path.addLine(to: CGPoint(x: p1.x, y: p1.y + radius))
            path.addArc(center: CGPoint(x: p1.x + radius, y: p1.y + radius), radius: radius, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        } else {
            path.addLine(to: p1)
        }
        
        path.closeSubpath()
        return path
    }
}

extension NSBezierPath {
    // Removed redundant/broken extensions
}

struct MessageListView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    var fontSize: Double
    var fontFamily: String
    @State private var scrollToBottomTrigger: Int = 0
    @State private var hiddenReasoningMessageIds: Set<UUID> = []
    
    var body: some View {
        LiquidGlassScrollView(.vertical, showsIndicators: false, scrollToBottomTrigger: scrollToBottomTrigger) {
            VStack(alignment: .leading, spacing: 12) {
                let displayedMessages = messages.filter { message in
                    if message.role == .assistant && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (message.reasoning?.isEmpty ?? true) && (message.toolCalls?.isEmpty ?? true) {
                        return false
                    }
                    return true
                }
                
                ForEach(displayedMessages) { message in
                    let isMessageEmpty = message.role == .assistant && 
                                        message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                                        (message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && 
                                        (message.toolCalls?.isEmpty ?? true)
                    
                    if isMessageEmpty {
                        // Skip rendering entirely
                    } else if message.isToolExecution {
                        let latestForId = displayedMessages.last { $0.toolCallId == message.toolCallId }
                        if message.id != latestForId?.id {
                            EmptyView()
                        } else {
                            MessageView(
                                message: message,
                                fontSize: fontSize,
                                fontFamily: fontFamily,
                                isReasoningHidden: Binding(
                                    get: { hiddenReasoningMessageIds.contains(message.id) },
                                    set: { isHidden in
                                        if isHidden {
                                            hiddenReasoningMessageIds.insert(message.id)
                                        } else {
                                            hiddenReasoningMessageIds.remove(message.id)
                                        }
                                    }
                                )
                            )
                            .id(message.id)
                        }
                    } else {
                        MessageView(
                            message: message,
                            fontSize: fontSize,
                            fontFamily: fontFamily,
                            isReasoningHidden: Binding(
                                get: { hiddenReasoningMessageIds.contains(message.id) },
                                    set: { isHidden in
                                        if isHidden {
                                            hiddenReasoningMessageIds.insert(message.id)
                                        } else {
                                            hiddenReasoningMessageIds.remove(message.id)
                                        }
                                    }
                                )
                            )
                            .id(message.id)
                    }
                }

                if isSending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Assistant is typing…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(16)
                    .frame(maxWidth: 400)
                }
            }
            .padding()
            .padding(.bottom, 120)
        }
        .onChange(of: messages.count) {
            // Increment trigger to scroll to bottom when new messages are added
            scrollToBottomTrigger += 1
        }
        .onAppear {
            // Initial scroll to bottom
            scrollToBottomTrigger += 1
        }
    }
}

struct MessageView: View {
    let message: ChatMessage
    var fontSize: Double
    var fontFamily: String
    @Binding var isReasoningHidden: Bool
    @State private var isExpanded = false
    @State private var showFullReasoning = false
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Tool Execution Message
                if message.isToolExecution {
                    // Only show the message if it's the latest for this tool call ID or if it's currently executing
                    // However, we don't have access to the full message list here.
                    // Let's assume the parent (MessageListView) handles filtering for consolidation if needed,
                    // but for now, we'll fix the double box by making it look like a single unit.
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Header (Always Visible)
                        HStack(spacing: 6) {
                            statusIcon
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.toolName ?? "Tool")
                                    .font(.system(size: CGFloat(max(10, fontSize - 2)), weight: .medium))
                                    .foregroundColor(.primary)
                                
                                if let file = message.targetFile {
                                    Text(file)
                                        .font(.system(size: CGFloat(max(9, fontSize - 4))))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            
                            Spacer()
                            
                            // Chevron for expansion
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(8, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                        
                        // Details/Output (Collapsible)
                        if isExpanded {
                            VStack(alignment: .leading) {
                                Divider()
                                Text(message.content)
                                    .font(resolveFont(size: fontSize - 2, family: fontFamily))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8, corners: [.bottomLeft, .bottomRight])
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 400) // Limit width of tool outputs
                } 
                // Standard Chat Message
                else {
                    let isMessageEmpty = message.role == .assistant && 
                                        message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
                                        (message.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && 
                                        (message.toolCalls?.isEmpty ?? true)
                    
                    if !isMessageEmpty {
                        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                            Text(message.role == .user ? "You" : "Assistant")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if message.role == .assistant, let reasoning = message.reasoning, !reasoning.isEmpty, !isReasoningHidden {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "brain")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Reasoning")
                                        .font(resolveFont(size: max(10, fontSize - 2), family: fontFamily))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Image(systemName: showFullReasoning ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showFullReasoning.toggle()
                                    }
                                }

                                Text(showFullReasoning ? reasoning : reasoningPreview(reasoning))
                                    .font(resolveFont(size: max(9, fontSize - 3), family: fontFamily))
                                    .foregroundColor(.secondary)
                                    .lineLimit(showFullReasoning ? nil : 5)

                                HStack(spacing: 8) {
                                    Button(showFullReasoning ? "Show less" : "Show more") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showFullReasoning.toggle()
                                        }
                                    }
                                    .buttonStyle(.borderless)

                                    Button("Hide") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isReasoningHidden = true
                                        }
                                    }
                                    .buttonStyle(.borderless)

                                    Spacer()
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(14)
                            .frame(maxWidth: 400)
                        }
                        
                        if message.role == .assistant {
                            MarkdownMessageView(
                                content: message.content,
                                fontSize: fontSize,
                                fontFamily: fontFamily
                            )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(backgroundColor(for: message))
                                .foregroundColor(foregroundColor(for: message))
                                .cornerRadius(16)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.content, forType: .string)
                                    } label: {
                                        Text("Copy Message")
                                        Image(systemName: "doc.on.doc")
                                    }
                                }
                        } else {
                            Text(message.content)
                                .font(.system(size: CGFloat(fontSize)))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(backgroundColor(for: message))
                                .foregroundColor(foregroundColor(for: message))
                                .cornerRadius(16)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(message.content, forType: .string)
                                    } label: {
                                        Text("Copy Message")
                                        Image(systemName: "doc.on.doc")
                                    }
                                }
                            }
                        }
                    }
                }
                
                if let codeContext = message.codeContext {
                    CodePreviewView(
                        code: codeContext,
                        fontSize: fontSize,
                        fontFamily: fontFamily
                    )
                }
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
    
    private func resolveFont(size: Double, family: String) -> Font {
        if let nsFont = NSFont(name: family, size: CGFloat(size)) {
            return Font(nsFont)
        }
        return .system(size: CGFloat(size), weight: .regular, design: .monospaced)
    }
    
    private var statusIcon: some View {
        Group {
            if message.toolStatus == .executing {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else if message.toolStatus == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if message.toolStatus == .failed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                Image(systemName: "gear")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
    }
    
    private var statusColor: Color {
        switch message.toolStatus {
        case .executing: return .orange
        case .completed: return .green
        case .failed: return .red
        default: return .gray
        }
    }
    
    private func backgroundColor(for message: ChatMessage) -> Color {
        return message.role == .user ? Color.blue : Color.gray.opacity(0.2)
    }
    
    private func foregroundColor(for message: ChatMessage) -> Color {
        return message.role == .user ? .white : .primary
    }

    private func reasoningPreview(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
        if lines.count <= 5 { return text }
        return lines.prefix(5).joined(separator: "\n") + "\n…"
    }
}

struct MessageListView_Previews: PreviewProvider {
    static var previews: some View {
        MessageListView(
            messages: [
                ChatMessage(role: .assistant, content: "Hello! How can I help you today?"),
                ChatMessage(role: .user, content: "Can you explain this code?"),
                ChatMessage(role: .assistant, content: "Sure! This code implements a chat interface."),
            ],
            isSending: true,
            fontSize: 12,
            fontFamily: "SF Mono"
        )
    }
}