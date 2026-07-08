import XCTest
@testable import osx_ide

/// Regression tests for the streaming tool-call argument corruption defect
/// (the `_raw_args_chunk` bug). The parser must never emit a tool call with
/// fabricated/garbage arguments; malformed calls are separated out instead.
final class ToolArgumentParserTests: XCTestCase {

    func testValidObjectIsParsed() {
        let drafts = [ToolArgumentDraft(id: "1", name: "read_file", arguments: "{\"path\":\"/a.swift\"}")]
        let result = ToolArgumentParser.assemble(drafts)
        XCTAssertTrue(result.malformed.isEmpty)
        XCTAssertEqual(result.valid.count, 1)
        XCTAssertEqual(result.valid[0].name, "read_file")
        XCTAssertEqual(result.valid[0].arguments["path"] as? String, "/a.swift")
    }

    func testNestedObjectIsParsed() {
        let json = "{\"a\":{\"b\":1,\"c\":[1,2]},\"d\":\"x\"}"
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "write_file", arguments: json)])
        XCTAssertTrue(result.malformed.isEmpty)
        XCTAssertEqual(result.valid.count, 1)
    }

    func testEmptyArgumentsYieldsEmptyArgs() {
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "run_command", arguments: "")])
        XCTAssertTrue(result.malformed.isEmpty)
        XCTAssertEqual(result.valid.count, 1)
        XCTAssertTrue(result.valid[0].arguments.isEmpty)
    }

    func testEmptyObjectYieldsEmptyArgs() {
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "run_command", arguments: "{}")])
        XCTAssertTrue(result.malformed.isEmpty)
        XCTAssertEqual(result.valid.count, 1)
        XCTAssertTrue(result.valid[0].arguments.isEmpty)
    }

    func testTruncatedArgumentsAreMalformed() {
        // Simulate a streamed argument buffer cut off mid-object.
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "read_file", arguments: "{\"path\":\"/a.swift\"")])
        XCTAssertEqual(result.malformed.count, 1)
        XCTAssertTrue(result.valid.isEmpty)
        // The engine must NOT dispatch a call with a fabricated argument key.
        XCTAssertNil(result.malformed[0].rawArguments.range(of: "_raw_args_chunk"))
    }

    func testTrailingCommaIsToleratedAsValid() {
        // Foundation's JSONSerialization is lenient about trailing commas, so
        // this must parse as valid rather than be flagged malformed.
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "read_file", arguments: "{\"path\":\"/a.swift\",}")])
        XCTAssertTrue(result.malformed.isEmpty)
        XCTAssertEqual(result.valid.count, 1)
    }

    func testNonJSONTextIsMalformed() {
        let result = ToolArgumentParser.assemble([ToolArgumentDraft(id: "1", name: "read_file", arguments: "path=/a.swift")])
        XCTAssertEqual(result.malformed.count, 1)
        XCTAssertTrue(result.valid.isEmpty)
    }

    func testMixedValidAndMalformed() {
        let drafts = [
            ToolArgumentDraft(id: "1", name: "read_file", arguments: "{\"path\":\"/a.swift\"}"),
            ToolArgumentDraft(id: "2", name: "read_file", arguments: "{\"path\":\"/b.swift\"")
        ]
        let result = ToolArgumentParser.assemble(drafts)
        XCTAssertEqual(result.valid.count, 1)
        XCTAssertEqual(result.malformed.count, 1)
        XCTAssertEqual(result.malformed[0].id, "2")
    }
}

/// Debt-regression: classification sets must only reference tools that actually
/// exist (registered tool names or known aliases). Dangling names like
/// `checkpoint_list` / `conversation_fold` previously caused `tool.not_found`.
final class ToolClassificationCatalogTests: XCTestCase {

    func testReadOnlyClassificationNamesHaveNoDanglingTools() {
        let dangling: Set<String> = ["checkpoint_list", "conversation_fold"]
        for name in MutationTools.readOnlyNames where dangling.contains(name) {
            XCTFail("Classification set references dangling tool name: \(name)")
        }
        for name in MutationTools.mutationNames where dangling.contains(name) {
            XCTFail("Mutation classification set references dangling tool name: \(name)")
        }
    }

    func testToolAliasRegistryResolvesCommonAliases() {
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "bash"), "run_command")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "find"), "find_file")
        XCTAssertEqual(ToolAliasRegistry.shared.canonicalName(for: "list_dir"), "list_files")
    }
}
