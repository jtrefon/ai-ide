//
//  EventBus.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import Foundation
import Combine

/// Marker protocol for all events in the system.
/// Events should be immutable structs containing data about what happened.
public protocol Event { }

/// Protocol for the system-wide Event Bus.
public protocol EventBusProtocol: Sendable {
    /// Publishes an event to all subscribers.
    func publish<E: Event>(_ event: E)

    /// Subscribes to a specific type of event.
    /// - Returns: A Cancellable generic that can be stored to manage subscription lifecycle.
    func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable
}

/// The concrete implementation of the Event Bus using Combine.
/// This acts as the central nervous system of the IDE.
/// Thread-safe but NOT isolated to @MainActor to avoid blocking background publishers.
public final class EventBus: EventBusProtocol, @unchecked Sendable {
    // We store PassthroughSubjects for each Event type name.
    // Using String keys (type name) allows decoupled storage.
    private var subjects: [String: Any] = [:]
    private let lock = NSLock()

    // Log sampling to avoid spawning a Task per event on hot paths
    private let logSampleRate: UInt64 = 100
    private var publishCounter: UInt64 = 0
    private var subscribeCounter: UInt64 = 0
    private let statsLock = NSLock()

    public init() {}

    public func publish<E: Event>(_ event: E) {
        let key = String(describing: E.self)

        // Log only every Nth publish to avoid spawning Tasks on hot paths
        statsLock.lock()
        publishCounter += 1
        let shouldLog = (publishCounter % logSampleRate == 0)
        statsLock.unlock()
        if shouldLog {
            Task {
                await AppLogger.shared.debug(
                    category: .eventBus,
                    message: "event.publish",
                    context: AppLogger.LogCallContext(metadata: [
                        "eventType": key,
                        "publishCount": String(publishCounter)
                    ])
                )
            }
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        if let subject = subjects[key] as? PassthroughSubject<E, Never> {
            subject.send(event)
        }
    }

    public func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
        let key = String(describing: E.self)

        // Log only every Nth subscribe
        statsLock.lock()
        subscribeCounter += 1
        let shouldLog = (subscribeCounter % logSampleRate == 0)
        statsLock.unlock()
        if shouldLog {
            Task {
                await AppLogger.shared.debug(
                    category: .eventBus,
                    message: "event.subscribe",
                    context: AppLogger.LogCallContext(metadata: [
                        "eventType": key
                    ])
                )
            }
        }
        
        lock.lock()
        defer { lock.unlock() }
        
        let subject: PassthroughSubject<E, Never>

        if let existing = subjects[key] as? PassthroughSubject<E, Never> {
            subject = existing
        } else {
            subject = PassthroughSubject<E, Never>()
            subjects[key] = subject
        }

        // Deliver events on main thread for UI updates
        return subject
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
}

public struct LocalModelStreamingChunkEvent: Event {
    public let runId: String
    public let chunk: String

    public init(runId: String, chunk: String) {
        self.runId = runId
        self.chunk = chunk
    }
}

public struct LocalModelStreamingStatusEvent: Event {
    public let runId: String
    public let message: String

    public init(runId: String, message: String) {
        self.runId = runId
        self.message = message
    }
}
public struct LocalModelStreamingReasoningChunkEvent: Event {
    public let runId: String
    public let chunk: String

    public init(runId: String, chunk: String) {
        self.runId = runId
        self.chunk = chunk
    }
}
