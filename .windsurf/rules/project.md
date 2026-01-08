---
trigger: always_on
---

# Project-Specific Rules for Swift and macOS Development

These rules extend the global rules with Swift and macOS-specific best practices, prioritizing native APIs and frameworks for optimal performance and integration.

## Principles

### SOLID (Adapted for Swift)

- **Single Responsibility Principle (SRP)**: Structs, classes, and enums should have one clear purpose; use protocols for shared behaviors.
- **Open/Closed Principle (OCP)**: Design types to be extensible via protocols and generics without modification.
- **Liskov Substitution Principle (LSP)**: Ensure subclasses and conforming types maintain behavioral contracts.
- **Interface Segregation Principle (ISP)**: Use fine-grained protocols to avoid forcing unnecessary dependencies.
- **Dependency Inversion Principle (DIP)**: Depend on protocols rather than concrete types.

### Swift Idioms

- **Value Semantics**: Prefer structs and enums over classes for data models to leverage immutability and safety.
- **Protocol-Oriented Programming**: Build abstractions with protocols and protocol extensions for flexibility and testability.
- **Error Handling**: Use Swift's `Result` and `throws` for explicit error propagation; avoid `try!` in production.
- **Optionals**: Handle optionals safely with `if let`, `guard let`, or `??`; avoid force unwrapping.

## Architecture

- **UI Framework**: Use SwiftUI for new interfaces; fall back to AppKit for complex legacy integrations. Prefer SwiftUI's declarative syntax.
- **Concurrency Model**: Employ Swift Concurrency (async/await, Task, Actor) for thread-safe operations; use MainActor for UI updates.
- **Dependency Injection**: Use Swift's type system and protocols for DI; avoid global singletons.
- **Event-Driven Communication**: Leverage Combine publishers and SwiftUI's state binding for reactive updates.
- **Modular Design**: Structure apps as Swift packages or frameworks; use SPM for dependency management.
- **State Management**: Use ObservableObject and @Published for SwiftUI state; consider TCA (The Composable Architecture) for complex apps.
- **Error Handling**: Standardize on Result<T, AppError> or custom error enums; use do-catch for synchronous errors.
- **Persistence**: Use Core Data or SwiftData for native persistence; SQLite via GRDB for custom needs. Prefer CloudKit for iCloud sync.
- **Domain Isolation**: Separate business logic into dedicated modules or packages.
- **Inversion of Control**: Use protocols and generics to invert dependencies.
- **Architecture Layering**: Follow MVVM for SwiftUI apps; use VIPER or similar for complex AppKit apps with clear separation of View, Interactor, Presenter, Entity, Router.
- **Data Streams**: Use Combine for reactive data flows; async sequences for async streams.
- **Data Structures**: Design Codable structs for data models; use enums for state machines and option sets.
- **Separation of Control**: Isolate view logic in ViewModels; use coordinators for navigation.

## Standards

- **Code Style**: Follow Swift API Design Guidelines; use swift-format for consistency.
- **Type Safety**: Leverage Swift's strong typing; use generics for reusable code; avoid Any and as!.
- **Documentation**: Use Swift's /// comments for API docs; generate with DocC.
- **Testing**: Use XCTest for unit tests; XCUITest for UI tests; Swift Testing framework for modern async testing.
- **Version Control**: Use Git with GitFlow; commit frequently with conventional commits.
- **Performance**: Profile with Instruments; use lazy properties and weak references to avoid retain cycles; prefer value types.
- **Security**: Use Keychain for sensitive data; enable App Sandbox; validate inputs with NSRegularExpression or Swift Regex.

## Paradigms

- **Protocol-Oriented Programming**: Core to Swift; use PATs (Protocol with Associated Types) for generic abstractions.
- **Functional Programming**: Use map, filter, reduce; leverage immutability with let bindings.
- **Reactive Programming**: Combine for handling asynchronous events and data streams.
- **Object-Oriented Design**: Use classes sparingly for reference semantics; prefer POP.
- **Declarative UI**: SwiftUI's primary paradigm; compose views declaratively.
- **Actor Model**: Use actors for shared mutable state to prevent data races.
- **Dependency Inversion**: Invert control with protocols and injection.
- **Domain-Driven Design**: Model domains with value types and protocols; use enums for domain-specific logic.

## macOS-Specific Best Practices

- **Native APIs**: Prefer AppKit/SwiftUI over cross-platform alternatives; use NSWorkspace, NSApplication for system integration.
- **Concurrency**: Use DispatchQueue.main for legacy; migrate to MainActor.
- **File System**: Use FileManager and URL for paths; enable App Sandbox entitlements.
- **Networking**: Use URLSession for HTTP; NWConnection for low-level networking.
- **Notifications**: Use NotificationCenter for app-internal; UNUserNotificationCenter for user notifications.
- **Accessibility**: Implement NSAccessibility protocols; test with Accessibility Inspector.
- **Localization**: Use NSLocalizedString and String catalogs.
- **App Lifecycle**: Handle NSApplicationDelegate methods properly.
- **Menus and Toolbars**: Use NSMenu and NSToolbar for native UX.
- **Window Management**: Leverage NSWindow and NSWindowController.
- **Security**: Use SecKeychain for credentials; code signing and notarization.

## Version-Specific Notes (macOS 15+)

- **Swift Concurrency**: Fully adopt async/await, Task Groups, and Actors.
- **SwiftUI Enhancements**: Use latest SwiftUI features like ScrollViewReader, FocusState.
- **SwiftData**: Prefer SwiftData over Core Data for new apps.
- **Vision Framework**: Integrate Vision for image analysis if applicable.
- **WidgetKit**: Use for dashboard widgets.
- **App Intents**: Implement for Siri and Shortcuts integration.
- **RealityKit**: For AR/VR features if needed.