//
//  AgentActivityCoordinator.swift
//  osx-ide
//
//  Coordinates agent activity tracking across all long-running operations.
//  Uses reference counting to manage power assertions for:
//  - API sending
//  - Tool execution (commands, downloads, compilations)
//  - MLX model inference
//  - RAG operations
//  - Indexing operations
//

import Foundation

/// Types of agent activities that prevent system sleep
public enum AgentActivityType: String, Sendable {
    case apiSending = "api_sending"
    case toolExecution = "tool_execution"
    case mlxInference = "mlx_inference"
    case ragRetrieval = "rag_retrieval"
    case indexing = "indexing"
    case embeddingGeneration = "embedding_generation"
    case modelDownload = "model_download"
}

/// Token representing an active agent activity.
/// Releases the activity when deallocated.
public final class AgentActivityToken: @unchecked Sendable {
    private let id: UUID
    private let type: AgentActivityType
    private weak var coordinator: AgentActivityCoordinator?
    private let lock = NSLock()
    private var hasEnded = false
    
    init(id: UUID, type: AgentActivityType, coordinator: AgentActivityCoordinator) {
        self.id = id
        self.type = type
        self.coordinator = coordinator
    }
    
    deinit {
        // Release the activity when token goes out of scope
        end()
    }
    
    /// Manually end the activity before token deallocation
    public func end() {
        lock.lock()
        defer { lock.unlock() }
        
        guard !hasEnded else { return }
        hasEnded = true
        
        coordinator?.releaseActivity(id: id, type: type)
    }
}

/// Protocol for agent activity coordination - allows mocking in tests
public protocol AgentActivityCoordinating: AnyObject, Sendable {
    /// Whether any agent activity is currently active
    var hasActiveActivities: Bool { get }
    
    /// Number of active activities
    var activeActivityCount: Int { get }
    
    /// Begin an agent activity, returning a token that releases when deallocated
    func beginActivity(type: AgentActivityType) -> AgentActivityToken
    
    /// Perform a scoped activity that automatically releases when complete
    func withActivity<T>(type: AgentActivityType, _ operation: @Sendable () async throws -> T) async rethrows -> T
}

/// Coordinates all agent activities to manage power assertions.
/// Uses reference counting to ensure power assertion is held while any activity is active.
/// Thread-safe via NSLock - can be accessed from any actor/queue.
public final class AgentActivityCoordinator: AgentActivityCoordinating, @unchecked Sendable {
    
    // MARK: - Properties
    
    /// Shared instance for global access
    public static let shared = AgentActivityCoordinator()
    
    /// Power management service to control sleep prevention
    private let powerManagementService: PowerManagementServiceProtocol
    
    /// Active activities by type for debugging and status display
    private var activitiesByType: [AgentActivityType: Set<UUID>] = [:]
    
    /// Lock for thread-safe access to activities
    private let lock = NSLock()
    
    /// Total count of active activities
    public var activeActivityCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activitiesByType.values.reduce(0) { $0 + $1.count }
    }
    
    /// Whether any agent activity is currently active
    public var hasActiveActivities: Bool {
        activeActivityCount > 0
    }
    
    // MARK: - Initialization
    
    init(powerManagementService: PowerManagementServiceProtocol = PowerManagementService()) {
        self.powerManagementService = powerManagementService
    }
    
    // MARK: - Public Methods
    
    /// Begin an agent activity, returning a token that releases when deallocated
    public func beginActivity(type: AgentActivityType) -> AgentActivityToken {
        let id = UUID()
        
        lock.lock()
        
        // Add to tracking
        if activitiesByType[type] == nil {
            activitiesByType[type] = []
        }
        activitiesByType[type]?.insert(id)
        
        let count = activitiesByType.values.reduce(0) { $0 + $1.count }
        
        logActivityStarted(type: type, id: id, totalCount: count)
        
        // Ensure power assertion is active
        updatePowerAssertionLocked()
        
        lock.unlock()
        
        return AgentActivityToken(id: id, type: type, coordinator: self)
    }
    
    /// Perform a scoped activity that automatically releases when complete
    public func withActivity<T>(type: AgentActivityType, _ operation: @Sendable () async throws -> T) async rethrows -> T {
        let token = beginActivity(type: type)
        defer { token.end() }
        return try await operation()
    }
    
    /// Release an activity by ID (called by token)
    func releaseActivity(id: UUID, type: AgentActivityType) {
        lock.lock()
        defer { lock.unlock() }
        
        // Remove from tracking
        activitiesByType[type]?.remove(id)
        
        // Clean up empty sets
        if activitiesByType[type]?.isEmpty == true {
            activitiesByType[type] = nil
        }
        
        let count = activitiesByType.values.reduce(0) { $0 + $1.count }
        
        logActivityEnded(type: type, id: id, totalCount: count)
        
        // Update power assertion state
        updatePowerAssertionLocked()
    }
    
    // MARK: - Private Methods
    
    /// Must be called while holding lock
    private func updatePowerAssertionLocked() {
        let hasActive = !activitiesByType.values.filter { !$0.isEmpty }.isEmpty
        
        if hasActive {
            // At least one activity active - ensure power assertion
            if !powerManagementService.isActive {
                powerManagementService.beginPreventingSleep()
            }
        } else {
            // No activities - release power assertion
            if powerManagementService.isActive {
                powerManagementService.stopPreventingSleep()
            }
        }
    }
    
    private func logActivityStarted(type: AgentActivityType, id: UUID, totalCount: Int) {
        print("[AgentActivity] Started: \(type.rawValue) (id: \(id.uuidString.prefix(8))), total active: \(totalCount)")
    }
    
    private func logActivityEnded(type: AgentActivityType, id: UUID, totalCount: Int) {
        print("[AgentActivity] Ended: \(type.rawValue) (id: \(id.uuidString.prefix(8))), total active: \(totalCount)")
    }
}

// MARK: - Convenience Extensions

extension AgentActivityCoordinator {
    /// Get a summary of active activities for debugging/display
    public var activitySummary: String {
        lock.lock()
        defer { lock.unlock() }
        
        guard hasActiveActivities else {
            return "No active agent activities"
        }
        
        let parts = activitiesByType.compactMap { type, ids -> String? in
            guard !ids.isEmpty else { return nil }
            return "\(type.rawValue): \(ids.count)"
        }
        
        return "Active: " + parts.joined(separator: ", ")
    }
    
    /// Check if a specific activity type is active
    public func isActivityTypeActive(_ type: AgentActivityType) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (activitiesByType[type]?.count ?? 0) > 0
    }
}
