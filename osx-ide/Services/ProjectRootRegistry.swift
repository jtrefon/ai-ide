import Foundation
import Combine

/// App-wide single source of truth for the active project root directory.
///
/// All subsystems that depend on the project path — terminal working directory,
/// file tree root, agentic sandboxing (`PathValidator`), codebase index,
/// conversation scoping — should read from this registry to guarantee
/// consistency.  Write access is restricted so the value can only be changed
/// through the official lifecycle path (see `WorkspaceLifecycleCoordinator`).
///
/// ## Initial value
///
/// The registry loads its initial value from the `PROJECT_ROOT` environment
/// variable if set, otherwise starts as `nil`.  This allows launcher scripts
/// or test harnesses to set the project root before any views are created:
///
/// ```sh
/// PROJECT_ROOT=/path/to/project open /Applications/osx-ide.app
/// ```
///
/// Once the workspace lifecycle fires, ``set(_:)`` replaces the env-var value
/// with the canonical workspace root (the two will agree in normal use).
///
/// ## Fan-out
///
/// Subscribe via the `@Published` publisher:
/// ```swift
/// let root = ProjectRootRegistry.shared.current          // sync read
/// ProjectRootRegistry.shared.$current.dropFirst().sink { … }  // changes
/// ```
@MainActor
final class ProjectRootRegistry: ObservableObject {
    static let shared = ProjectRootRegistry()

    /// The current project root, or `nil` if no project is open.
    @Published private(set) var current: URL?

    private init() {
        current = Self.loadOverride()
    }

    /// Called by `WorkspaceLifecycleCoordinator` when the workspace root changes.
    /// Standardises the URL (resolves symlinks, standardises path) so consumers
    /// always see the same canonical representation.
    func set(_ url: URL) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if current != canonical {
            current = canonical
        }
    }

    /// Called when all projects are closed.
    func clear() {
        current = nil
    }

    /// Seeds the registry from `PROJECT_ROOT` env var so that consumers created
    /// before ``set(_:)`` is called (e.g. the terminal) still see a valid path.
    private static func loadOverride() -> URL? {
        guard let raw = ProcessInfo.processInfo.environment["PROJECT_ROOT"], !raw.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: raw).standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }
}
