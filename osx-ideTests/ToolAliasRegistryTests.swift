import XCTest
@testable import osx_ide

final class ToolAliasRegistryTests: XCTestCase {
    func testCanonicalNamePassesThroughUnknown() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "unknown_tool"), "unknown_tool")
    }

    func testCanonicalNameResolvesAlias() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "list_directory"), "ls")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "list_dir"), "ls")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "create_file"), "write")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "edit_file"), "edit")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "view_file"), "read")
    }

    func testCanonicalNameIsCaseInsensitive() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "LIST_DIRECTORY"), "ls")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "Create_File"), "write")
    }

    func testCanonicalNameTrimsWhitespace() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "  list_dir  "), "ls")
    }

    func testAllWebAliases() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "web_fetch"), "web_fetch")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "fetch_url"), "web_fetch")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "browse"), "web_fetch")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "internet_search"), "web_search")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "search_web"), "web_search")
    }

    func testAllTerminalAliases() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "run_shell"), "bash")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "bash"), "bash")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "run_terminal_command"), "bash")
    }

    func testCustomRegistration() {
        let registry = ToolAliasRegistry()
        registry.register(alias: "my_custom", canonical: "my_tool")
        XCTAssertEqual(registry.canonicalName(for: "my_custom"), "my_tool")
    }

    func testCustomRegistrationOverridesBuiltin() {
        let registry = ToolAliasRegistry()
        registry.register(alias: "list_dir", canonical: "custom_list")
        XCTAssertEqual(registry.canonicalName(for: "list_dir"), "custom_list")
    }
}
