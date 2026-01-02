//
//  ChatHistoryManager.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import SwiftUI

/// Manages the persistence and state of chat messages.
@MainActor
public class ChatHistoryManager: ObservableObject {
    @Published public var messages: [ChatMessage] = []
    private let historyKey = "AIChatHistory"
    
    public init() {
        loadHistory()
        if messages.isEmpty {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Hello! I'm your AI coding assistant. How can I help you today?"
            ))
        }
    }
    
    public func append(_ message: ChatMessage) {
        messages.append(message)
        saveHistory()
    }
    
    public func removeLast() {
        if !messages.isEmpty {
            messages.removeLast()
            saveHistory()
        }
    }
    
    public func clear() {
        messages.removeAll()
        messages.append(ChatMessage(
            role: .assistant,
            content: "Conversation cleared. How can I assist you now?"
        ))
        saveHistory()
    }
    
    public func saveHistory() {
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("Failed to save conversation history: \(error)")
        }
    }
    
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        
        do {
            messages = try JSONDecoder().decode([ChatMessage].self, from: data)
        } catch {
            print("Failed to load conversation history: \(error)")
        }
    }
}
