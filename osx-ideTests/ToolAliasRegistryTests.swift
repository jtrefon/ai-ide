import XCTest
@testable import osx_ide

final class ToolAliasRegistryTests: XCTestCase {
    func testCanonicalNamePassesThroughUnknown() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "unknown_tool"), "unknown_tool")
    }

    func testCanonicalNameResolvesAlias() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "list_directory"), "list_files")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "list_dir"), "list_files")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "create_file"), "write_file")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "edit_file"), "replace_in_file")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "view_file"), "read_file")
    }

    func testCanonicalNameIsCaseInsensitive() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "LIST_DIRECTORY"), "list_files")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "Create_File"), "write_file")
    }

    func testCanonicalNameTrimsWhitespace() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "  list_dir  "), "list_files")
    }

    func testAllWebAliases() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "web_fetch"), "web_browse")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "fetch_url"), "web_browse")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "browse"), "web_browse")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "internet_search"), "web_search")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "search_web"), "web_search")
    }

    func testAllTerminalAliases() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "run_shell"), "run_command")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "bash"), "run_command")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "run_terminal_command"), "run_command")
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
