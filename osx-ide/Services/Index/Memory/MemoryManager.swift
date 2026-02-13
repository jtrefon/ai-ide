//
//  MemoryManager.swift
//  osx-ide
//
//  Created by Cascade on 23/12/2025.
//

import Foundation

public enum MemoryError: Error {
    case confirmationRequired(MemoryEntry)
    case explicitApprovalRequired(MemoryEntry)
    case notFound
}

public actor MemoryManager {
    private let database: DatabaseStore
    private let eventBus: EventBusProtocol
    private let embeddingGenerator: any MemoryEmbeddingGenerating

    public init(
        database: DatabaseStore,
        eventBus: EventBusProtocol,
        embeddingGenerator: any MemoryEmbeddingGenerating = HashingMemoryEmbeddingGenerator()
    ) {
        self.database = database
        self.eventBus = eventBus
        self.embeddingGenerator = embeddingGenerator
    }

    public func addMemory(content: String, tier: MemoryTier, category: String) async throws -> MemoryEntry {
        let entry = MemoryEntry(
            tier: tier,
            content: content,
            category: category,
            protectionLevel: 0
        )

        // Calculate initial protection level
        let protection = ProtectionCalculator.calculate(for: entry)
        let protectedEntry = MemoryEntry(
            id: entry.id,
            tier: entry.tier,
            content: entry.content,
            category: entry.category,
            timestamp: entry.timestamp,
            protectionLevel: protection
        )

        try await database.saveMemory(protectedEntry)
        await persistEmbeddingIfNeeded(entry: protectedEntry)
        Task { @MainActor in
            eventBus.publish(MemoryCapturedEvent(tier: tier.rawValue, content: content))
        }

        return protectedEntry
    }

    public func updateMemory(id: String, newContent: String, force: Bool = false) async throws -> MemoryEntry {
        // First retrieve existing
        let memories = try await database.getMemories()
        guard let entry = memories.first(where: { $0.id == id }) else {
            throw MemoryError.notFound
        }

        // Check protection
        if !force {
            if ProtectionCalculator.requiresExplicitApproval(level: entry.protectionLevel) {
                throw MemoryError.explicitApprovalRequired(entry)
            }
            if ProtectionCalculator.requiresConfirmation(level: entry.protectionLevel) {
                throw MemoryError.confirmationRequired(entry)
            }
        }

        let updatedEntry = MemoryEntry(
            id: entry.id,
            tier: entry.tier,
            content: newContent,
            category: entry.category,
            timestamp: entry.timestamp,
            protectionLevel: entry.protectionLevel
        )

        // Recalculate protection
        let newProtection = ProtectionCalculator.calculate(for: updatedEntry)
        let finalEntry = MemoryEntry(
            id: updatedEntry.id,
            tier: updatedEntry.tier,
            content: updatedEntry.content,
            category: updatedEntry.category,
            timestamp: updatedEntry.timestamp,
            protectionLevel: newProtection
        )

        try await database.saveMemory(finalEntry)
        await persistEmbeddingIfNeeded(entry: finalEntry)
        return finalEntry
    }

    public func deleteMemory(id: String, force: Bool = false) async throws {
        let memories = try await database.getMemories()
        guard let entry = memories.first(where: { $0.id == id }) else {
            throw MemoryError.notFound
        }

        if !force {
            if ProtectionCalculator.requiresExplicitApproval(level: entry.protectionLevel) {
                throw MemoryError.explicitApprovalRequired(entry)
            }
            if ProtectionCalculator.requiresConfirmation(level: entry.protectionLevel) {
                throw MemoryError.confirmationRequired(entry)
            }
        }

        try await database.deleteMemory(id: id)
    }

    public func getMemories(tier: MemoryTier? = nil) async throws -> [MemoryEntry] {
        return try await database.getMemories(tier: tier)
    }

    private func persistEmbeddingIfNeeded(entry: MemoryEntry) async {
        guard entry.tier == .longTerm else { return }

        do {
            let vector = try await embeddingGenerator.generateEmbedding(for: entry.content)
            guard !vector.isEmpty else { return }
            try await database.saveMemoryEmbedding(
                memoryId: entry.id,
                modelId: embeddingGenerator.modelIdentifier,
                vector: vector
            )
        } catch {
            return
        }
    }
}
