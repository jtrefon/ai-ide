//
//  MessageListView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI
import Foundation

struct MessageListView: View {
    let messages: [ChatMessage]
    let isSending: Bool
    @State private var scrollToBottomTrigger: Int = 0
    
    var body: some View {
        LiquidGlassScrollView(.vertical, showsIndicators: false, scrollToBottomTrigger: scrollToBottomTrigger) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    MessageView(message: message)
                        .id(message.id)
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
    @State private var isExpanded = false
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Tool Execution Message
                if message.isToolExecution {
                    VStack(alignment: .leading, spacing: 8) {
                        // Header (Always Visible)
                        HStack(spacing: 6) {
                            statusIcon
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.toolName ?? "Tool")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                if let file = message.targetFile {
                                    Text(file)
                                        .font(.system(size: 10))
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
                        .cornerRadius(8)
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
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            }
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 400) // Limit width of tool outputs
                } 
                // Standard Chat Message
                else {
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        Text(message.role == .user ? "You" : "Assistant")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if message.role == .assistant {
                            MarkdownMessageView(content: message.content)
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
                
                if let codeContext = message.codeContext {
                    CodePreviewView(code: codeContext)
                }
            }
            
            if message.role == .assistant {
                Spacer()
            }
        }
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
}

struct MessageListView_Previews: PreviewProvider {
    static var previews: some View {
        MessageListView(
            messages: [
                ChatMessage(role: .assistant, content: "Hello! How can I help you today?"),
                ChatMessage(role: .user, content: "Can you explain this code?"),
                ChatMessage(role: .assistant, content: "Sure! This code implements a chat interface."),
            ],
            isSending: true
        )
    }
}