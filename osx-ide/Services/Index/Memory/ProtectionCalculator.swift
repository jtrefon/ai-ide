//
//  ProtectionCalculator.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public struct ProtectionCalculator {
    public static func calculate(for entry: MemoryEntry, existingEntries: [MemoryEntry] = []) -> Int {
        var score = 0

        // Base score by tier
        switch entry.tier {
        case .shortTerm:
            score += 10
        case .midTerm:
            score += 40
        case .longTerm:
            score += 80
        }

        // Age factor (older = more protected)
        // Cap age bonus at 20 points for 30 days
        let age = Date().timeIntervalSince(entry.timestamp)
        let dayInSeconds: TimeInterval = 86400
        let daysOld = age / dayInSeconds
        let ageBonus = min(20, Int(daysOld * 0.5))
        score += ageBonus

        // Explicit protection (if we add a flag for it later)
        // For now, assume certain categories are more protected
        if entry.category == "architecture" || entry.category == "security" {
            score += 15
        }

        // Cap at 100
        return min(100, score)
    }

    public static func requiresConfirmation(level: Int) -> Bool {
        return level >= 50
    }

    public static func requiresExplicitApproval(level: Int) -> Bool {
        return level >= 80
    }
}
