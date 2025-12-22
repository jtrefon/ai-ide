//
//  CommandRegistry.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import Foundation

/// A unique identifier for a command, e.g., "editor.save" or "git.commit".
public struct CommandID: Hashable, ExpressibleByStringLiteral, CustomStringConvertible, Sendable {
    public let value: String
    
    public init(_ value: String) {
        self.value = value
    }
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public var description: String { value }
}

/// Protocol for any handler that can execute a command.
@MainActor
public protocol CommandHandler {
    func execute(args: [String: Any]) async throws
}

/// A closure-based command handler for convenience.
@MainActor
public final class ClosureCommandHandler: CommandHandler {
    private let action: @MainActor @Sendable ([String: Any]) async throws -> Void
    
    public init(_ action: @escaping @MainActor @Sendable ([String: Any]) async throws -> Void) {
        self.action = action
    }
    
    public func execute(args: [String: Any]) async throws {
        try await action(args)
    }
}

/// The centralized registry for all application commands.
/// This allows plugins to register behavior and the UI to trigger it blindly.
@MainActor
public final class CommandRegistry {
    public static let shared = CommandRegistry()
    
    private var handlers: [CommandID: CommandHandler] = [:]
    
    public init() {}
    
    /// Registers a handler for a command. Throws if the command is already registered?
    /// For now, we allow overwriting (Last-Writer-Wins) which enables "Hijacking".
    public func register(command: CommandID, handler: CommandHandler) {
        handlers[command] = handler
        print("[CommandRegistry] Registered: \(command)")
    }
    
    public func register(command: CommandID, action: @escaping @MainActor @Sendable ([String: Any]) async throws -> Void) {
        register(command: command, handler: ClosureCommandHandler(action))
    }
    
    public func unregister(command: CommandID) {
        handlers.removeValue(forKey: command)
        print("[CommandRegistry] Unregistered: \(command)")
    }
    
    public func execute(_ command: CommandID, args: [String: Any] = [:]) async throws {
        guard let handler = handlers[command] else {
            print("[CommandRegistry] Error: Command not found: \(command)")
            // TODO: Throw a proper error type
            return
        }
        
        print("[CommandRegistry] Executing: \(command)")
        try await handler.execute(args: args)
    }
}
