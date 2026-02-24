# Architecture Documentation

## Overview

The osx-ide is a modern macOS IDE built with SwiftUI and AppKit, designed to provide a powerful yet intuitive development environment. The architecture follows SOLID principles and emphasizes modularity, testability, and maintainability.

## Core Architecture

### Layered Architecture

The application follows a layered architecture pattern:

```
┌─────────────────────────────────────────┐
│              UI Layer                    │
│  SwiftUI Views + AppKit Components      │
├─────────────────────────────────────────┤
│            Service Layer                 │
│  Business Logic + State Management      │
├─────────────────────────────────────────┤
│            Core Layer                   │
│  Utilities + Protocols + Models        │
├─────────────────────────────────────────┤
│           Data Layer                    │
│  File System + Database + Persistence   │
└─────────────────────────────────────────┘
```

### Key Components

#### 1. UI Layer (`Components/`)

- **CodeEditorView**: Main code editor with syntax highlighting
- **ModernFileTreeCoordinator**: File tree navigation and management
- **MessageListView**: Chat interface for AI interactions
- **CommandPaletteOverlayView**: Quick command execution

#### 2. Service Layer (`Services/`)

- **WorkspaceService**: Project and file management
- **ConversationManager**: AI chat and conversation handling
- **AIToolExecutor**: Tool execution and sandboxing
- **IndexCoordinator**: Code indexing and symbol resolution
- **PowerManagementService**: Prevents system sleep during agent activity

#### 3. Core Layer (`Core/`)

- **CommandRegistry**: Command registration and execution
- **EventBus**: Event-driven communication
- **DependencyContainer**: Dependency injection

#### 4. Data Layer

- **DatabaseManager**: SQLite database operations
- **FileSystemService**: File system abstraction
- **IndexDatabase**: Symbol and code indexing storage

## Design Patterns

### 1. Dependency Injection

The application uses dependency injection through the `DependencyContainer`:

```swift
class DependencyContainer {
    static let shared = DependencyContainer()
    
    func registerServices() {
        register(WorkspaceService.self) { WorkspaceService() }
        register(ConversationManager.self) { ConversationManager() }
        // ... other services
    }
}
```

### 2. Observer Pattern

Event-driven communication using the `EventBus`:

```swift
protocol EventBusProtocol {
    func publish<T: Event>(_ event: T)
    func subscribe<T: Event>(to type: T.Type, handler: @escaping (T) -> Void)
}
```

### 3. Coordinator Pattern

UI coordination using coordinators:

```swift
class ModernFileTreeCoordinator {
    private let configuration: Configuration
    private weak var outlineView: NSOutlineView?
    
    func attach(outlineView: NSOutlineView) {
        // Setup and coordination logic
    }
}
```

### 4. Strategy Pattern

Tool execution using strategy pattern:

```swift
protocol AITool {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get }
    func execute(arguments: ToolArguments) async throws -> String
}
```

## Key Architectural Decisions

### 1. SwiftUI + AppKit Hybrid

- **SwiftUI** for modern, declarative UI
- **AppKit** for complex components (NSTextView, NSOutlineView)
- **Bridging** through NSViewRepresentable

### 2. Actor-Based Concurrency

- **@MainActor** for UI components
- **Actor** for shared mutable state
- **Async/Await** for asynchronous operations

#### Concurrency Patterns

**1. MainActor Isolation**

```swift
@MainActor
class ConversationManager {
    // All properties and methods are automatically isolated to main actor
    @Published var messages: [ChatMessage] = []
    
    func sendMessage() {
        // Safe to update UI state directly
    }
}
```

**2. Actor for Thread-Safe State**

```swift
actor DatabaseManager {
    private var cache: [String: Data] = [:]
    
    func get(_ key: String) -> Data? {
        cache[key]
    }
    
    func set(_ key: String, value: Data) {
        cache[key] = value
    }
}
```

**3. Task-Based Async Work**

```swift
// For non-MainActor async work
Task {
    let result = try await someAsyncOperation()
    await MainActor.run {
        // Update UI on main actor
        self.updateUI(result)
    }
}

// For MainActor work
Task { @MainActor in
    self.updateUI()
}
```

**4. Debouncing with Task**

```swift
private func debounceSearch() {
    searchTask?.cancel()
    searchTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 250_000_000)
        if !Task.isCancelled {
            performSearch()
        }
    }
}
```

### 3. Modular Tool System

- **Protocol-based** tool definitions
- **Sandboxed** execution environment
- **Extensible** architecture for new tools

### 4. Event-Driven Communication

- **Loose coupling** between components
- **Reactive** state management
- **Testable** event handling

### 5. Error Handling

- **Typed errors** using Swift's `Error` protocol
- **Context-rich error messages** with operation context
- **Graceful degradation** for non-critical failures

### 6. Power Management

The IDE prevents macOS sleep/screen saver during agent activity to ensure long-running operations complete successfully.

**Implementation:**

- **PowerManagementService**: Uses IOKit power assertions (`IOPMAssertionCreateWithName`) to prevent system sleep
- **Automatic lifecycle**: Assertions are created when agent becomes active (`isSending = true`) and released when idle
- **Power-conscious**: Uses `kIOPMAssertPreventUserIdleSystemSleep` which prevents system sleep but allows display to dim

```swift
@MainActor
final class PowerManagementService: PowerManagementServiceProtocol {
    func beginPreventingSleep() -> Bool {
        // Creates IOKit power assertion
        IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName,
            &assertionID
        )
    }
    
    func stopPreventingSleep() {
        // Releases assertion, normal sleep behavior resumes
        IOPMAssertionRelease(assertionID)
    }
}
```

**Integration with ConversationManager:**

The service observes `isSending` state changes and automatically manages power assertions:

```swift
$isSending
    .removeDuplicates()
    .sink { [weak self] isSending in
        if isSending {
            powerManagementService.beginPreventingSleep()
        } else {
            powerManagementService.stopPreventingSleep()
        }
    }
```

**Safety guarantees:**

- macOS automatically cleans up orphaned assertions if app crashes
- Service is idempotent - multiple calls to begin/stop are safe
- Protocol-based design allows mocking in unit tests

#### Crash & Exception Capture (Centralized)

The IDE treats **any caught/thrown error** as a signal for quality improvement. We capture errors **centrally** with:

- **Operation context** (a stable string describing what we were doing)
- **Callsite** (`file`, `function`, `line`)
- **Optional metadata** (key/value strings)

This is implemented by:

- `ErrorManager` (the centralized entry point for UI + error normalization)
- `CrashReporter` (the centralized persistence engine)

**Log location (project-scoped):**

- `.ide/logs/crash.ndjson`

**Log format:** newline-delimited JSON (NDJSON), one event per line.

**Event schema (CrashReportEvent):**

```json
{
  "ts": "2026-01-12T09:12:31Z",
  "session": "<uuid>",
  "operation": "WorkspaceService.rename",
  "errorType": "Foundation.NSError",
  "errorDescription": "File not found",
  "file": "Services/WorkspaceService.swift",
  "function": "rename(from:to:)",
  "line": 123,
  "metadata": {
    "path": "src/Foo.swift"
  }
}
```

**How errors flow:**

- Code catches an error and calls `errorManager.handle(error, context: "SomeOperation")`
- `ErrorManager` converts to `AppError` for UI display
- `ErrorManager` always invokes `CrashReporter.shared.capture(...)`
- `CrashReporter` writes the event to `.ide/logs/crash.ndjson` (and to App Support logs when no project root is set)

#### Error Handling Patterns

**1. Custom Error Types**

```swift
enum AppError: Error {
    case fileNotFound(path: String)
    case invalidOperation(String)
    case aiServiceError(String)
    
    var localizedDescription: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidOperation(let msg):
            return "Invalid operation: \(msg)"
        case .aiServiceError(let msg):
            return "AI service error: \(msg)"
        }
    }
}
```

**2. Context-Rich Error Conversion**

```swift
extension WorkspaceService {
    private func mapToAppError(_ error: Error, operation: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .unknown("\(operation): \(error.localizedDescription)")
    }
    
    func deleteFile(at url: URL) throws {
        do {
            try fileSystemService.deleteFile(at: url)
        } catch {
            throw mapToAppError(error, operation: "deleteFile")
        }
    }
}
```

**3. Result-Based Error Handling**

```swift
func loadFile(at url: URL) -> Result<String, AppError> {
    do {
        let content = try fileSystemService.readFile(at: url)
        return .success(content)
    } catch {
        return .failure(.fileNotFound(path: url.path))
    }
}
```

## Data Flow

```
User Input → UI Component → Service → Core/Database → Response
    ↑                                                    ↓
UI Update ← Event Bus ← Service Response ← Core/Database
```

## State Management

### 1. SwiftUI State

- **@State** for local component state
- **@StateObject** for shared state objects
- **@EnvironmentObject** for global state

### 2. Service State

- **@MainActor** for UI-related services
- **Actor** for thread-safe state management
- **Combine** publishers for reactive updates

### 3. Persistence

- **SQLite** for structured data
- **File System** for project files
- **UserDefaults** for preferences

## Testing Architecture

### 1. Unit Tests

- ** XCTest** framework
- **Dependency Injection** for mocking
- **Test Doubles** for external dependencies

### 2. UI Tests

- **XCUITest** framework
- **Accessibility** identifiers
- **Page Object** pattern

### 3. Integration Tests

- **End-to-end** workflows
- **Database** testing
- **File System** testing

## Performance Considerations

### 1. Incremental Highlighting

- **Change detection** for syntax highlighting
- **Caching** of previous results
- **Async** processing

### 2. Lazy Loading

- **On-demand** file indexing
- **Virtualized** lists
- **Background** processing

### 3. Memory Management

- **Weak references** to avoid retain cycles
- **Value types** for data models
- **Actor isolation** for shared state

## Security

### 1. Tool Sandboxing

- **Restricted** file system access
- **Validation** of tool inputs
- **Error handling** for malicious inputs

### 2. Data Protection

- **Keychain** for sensitive data
- **App Sandbox** entitlements
- **Input validation** throughout

## Extensibility

### 1. Plugin Architecture

- **Protocol-based** plugin system
- **Dynamic** loading of tools
- **Configuration** driven behavior

### 2. Language Support

- **Modular** syntax highlighting
- **Extensible** language modules
- **Fallback** highlighting system

## Future Considerations

### 1. Multi-Platform Support

- **Abstract** platform-specific code
- **Shared** business logic
- **Platform** adapters

### 2. Cloud Integration

- **Sync** capabilities
- **Collaborative** features
- **Remote** development

### 3. Advanced AI Features

- **Context-aware** assistance
- **Code generation**
- **Refactoring** suggestions

## Conclusion

The architecture of osx-ide emphasizes modularity, testability, and maintainability while providing a powerful development experience. The combination of modern Swift patterns with proven architectural principles ensures the application can evolve and scale over time.
