//
//  MemoryModels.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public enum MemoryTier: String, Codable, Sendable {
    case shortTerm // Fluid, current context
    case midTerm   // Protected, feature decisions
    case longTerm  // Sacred, architectural rules
}

public struct MemoryEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let tier: MemoryTier
    public let content: String
    public let category: String // e.g., "decision", "architecture", "pattern"
    public let timestamp: Date
    public let protectionLevel: Int // 0-100, computed
    
    public init(id: String = UUID().uuidString, tier: MemoryTier, content: String, category: String, timestamp: Date = Date(), protectionLevel: Int = 0) {
        self.id = id
        self.tier = tier
        self.content = content
        self.category = category
        self.timestamp = timestamp
        self.protectionLevel = protectionLevel
    }
}
