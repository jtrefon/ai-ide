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
public protocol EventBusProtocol {
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
    public static let shared = EventBus()
    
    // We store PassthroughSubjects for each Event type name.
    // Using String keys (type name) allows decoupled storage.
    private var subjects: [String: Any] = [:]
    
    public init() {}
    
    public func publish<E: Event>(_ event: E) {
        let key = String(describing: E.self)
        if let subject = subjects[key] as? PassthroughSubject<E, Never> {
            subject.send(event)
        }
    }
    
    public func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
        let key = String(describing: E.self)
        let subject: PassthroughSubject<E, Never>
        
        if let existing = subjects[key] as? PassthroughSubject<E, Never> {
            subject = existing
        } else {
            subject = PassthroughSubject<E, Never>()
            subjects[key] = subject
        }
        
        return subject
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: handler)
    }
}
