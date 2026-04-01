import XCTest
@testable import osx_ide

@MainActor
final class CompletionContextAssemblerTests: XCTestCase {
    func testBuildContextSplitsPrefixAndSuffixAroundCursor() {
        let assembler = CompletionContextAssembler()
        let buffer = """
        struct Greeter {
            func greet(name: String) {
                print(name)
            }
        }
        """
        let cursor = (buffer as NSString).range(of: "print").location
        let snapshot = InlineCompletionEditorSnapshot(
            paneID: .primary,
            filePath: "/tmp/Greeter.swift",
            language: "swift",
            buffer: buffer,
            cursorPosition: cursor,
            selectionLength: 0,
            triggerReason: .automatic
        )

        let context = assembler.buildContext(from: snapshot)
        XCTAssertTrue(context.prefix.contains("func greet"))
        XCTAssertTrue(context.suffix.contains("print"))
        XCTAssertEqual(context.scopeSummary, "func greet(name: String) {")
        XCTAssertTrue(context.symbols.contains("name"))
    }
}
