import Testing
import SwiftUI
@testable import osx_ide

// MARK: - Nucleus Architecture Tests

@Suite("Nucleus Architecture Tests")
@MainActor
struct NucleusSuite {

    @Test func commandRegistryExecution() async throws {
        let registry = CommandRegistry()
        let commandID: CommandID = "test.command"
        var executed = false

        registry.register(command: commandID) { _ in
            executed = true
        }

        try await registry.execute(commandID)
        #expect(executed, "Command handler should have been executed")
    }

    @Test func commandRegistryHijacking() async throws {
        let registry = CommandRegistry()
        let commandID: CommandID = "test.hijack"
        var result = ""

        // Initial registration
        registry.register(command: commandID) { _ in
            result = "original"
        }

        // Hijack
        registry.register(command: commandID) { _ in
            result = "hijacked"
        }

        try await registry.execute(commandID)
        #expect(result == "hijacked", "Last registered handler should win (Hijacking)")
    }

    @Test func typedCommandRegistryExecution() async throws {
        let registry = CommandRegistry()
        let cmd = TypedCommand<ExplorerRenameArgs>("test.rename")
        var seen: ExplorerRenameArgs? = nil

        registry.register(command: cmd) { args in
            seen = args
        }

        try await registry.execute(cmd, args: ExplorerRenameArgs(path: "/tmp/a.txt", newName: "b.txt"))
        #expect(seen?.path == "/tmp/a.txt")
        #expect(seen?.newName == "b.txt")
    }

    @Test func typedCommandRegistryCompatibleWithLegacyArgs() async throws {
        let registry = CommandRegistry()
        let cmd = TypedCommand<ExplorerPathArgs>("test.path")
        var seen: String? = nil

        registry.register(command: cmd) { args in
            seen = args.path
        }

        try await registry.execute(cmd.id, args: ["path": "/tmp/file.txt"])
        #expect(seen == "/tmp/file.txt")
    }

    @Test func uiRegistryRegistration() async throws {
        let registry = UIRegistry()
        let point: ExtensionPoint = .sidebarLeft

        // Ensure empty initially
        #expect(registry.views(for: point).isEmpty)

        // Register view (Using EmptyView for simplicity as AnyView)
        registry.register(point: point, name: "TestView", icon: "star", view: SwiftUI.EmptyView())

        // Verify
        let views = registry.views(for: point)
        #expect(views.count == 1)
        #expect(views.first?.name == "TestView")
        #expect(views.first?.iconName == "star")
    }
}
