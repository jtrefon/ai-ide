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
@MainActor
public protocol EventBusProtocol: Sendable {
    /// Publishes an event to all subscribers.
    func publish<E: Event>(_ event: E)

    /// Subscribes to a specific type of event.
    /// - Returns: A Cancellable generic that can be stored to manage subscription lifecycle.
    func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable
}

/// The concrete implementation of the Event Bus using Combine.
/// This acts as the central nervous system of the IDE.
@MainActor
public final class EventBus: EventBusProtocol {
    // We store PassthroughSubjects for each Event type name.
    // Using String keys (type name) allows decoupled storage.
    private var subjects: [String: Any] = [:]

    public init() {}

    public func publish<E: Event>(_ event: E) {
        let key = String(describing: E.self)

        Task {
            await AppLogger.shared.debug(
                category: .eventBus,
                message: "event.publish",
                context: AppLogger.LogCallContext(metadata: [
                    "eventType": key
                ])
            )
        }
        if let subject = subjects[key] as? PassthroughSubject<E, Never> {
            subject.send(event)
        }
    }

    public func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
        let key = String(describing: E.self)

        Task {
            await AppLogger.shared.debug(
                category: .eventBus,
                message: "event.subscribe",
                context: AppLogger.LogCallContext(metadata: [
                    "eventType": key
                ])
            )
        }
        let subject: PassthroughSubject<E, Never>

        if let existing = subjects[key] as? PassthroughSubject<E, Never> {
            subject = existing
        } else {
            subject = PassthroughSubject<E, Never>()
            subjects[key] = subject
        }

        // EventBus is @MainActor; publish() is expected to be called from the main actor.
        // Delivering synchronously here avoids races/flakiness in tests and keeps UI updates deterministic.
        return subject
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
