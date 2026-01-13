import Testing
import Foundation
import AppKit
@testable import osx_ide

@MainActor
struct SearchNavigationTests {

    @Test func testQuickOpenParseQuerySupportsLineSuffix() async throws {
        let parsed1 = QuickOpenOverlayView.parseQuery("Sources/Foo.swift:12")
        #expect(parsed1.fileQuery == "Sources/Foo.swift")
        #expect(parsed1.line == 12)

        let parsed2 = QuickOpenOverlayView.parseQuery("Foo.swift")
        #expect(parsed2.fileQuery == "Foo.swift")
        #expect(parsed2.line == nil)
    }

    @Test func testWorkspaceSearchParseIndexedMatchLine() async throws {
        let parsedMatch = WorkspaceSearchService.parseIndexedMatchLine("src/main.swift:42: print(\"hi\")")
        #expect(parsedMatch?.relativePath == "src/main.swift")
        #expect(parsedMatch?.line == 42)
        #expect(parsedMatch?.snippet == "print(\"hi\")")
    }

    @Test func testWorkspaceSearchFallbackFindsMatches() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_global_search_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        try "let x = 1\nlet y = 2\nprint(\"needle\")\n".write(to: file, atomically: true, encoding: .utf8)

        let svc = WorkspaceSearchService(codebaseIndexProvider: { nil })
        let results = await svc.search(pattern: "needle", projectRoot: tempRoot, limit: 20)
        let found = results.first(where: { $0.relativePath == "a.swift" })
        #expect(found != nil)
        #expect(found?.line == 3)
    }

    @Test func testCommandPaletteScoring() async throws {
        let exact = CommandPaletteScoring.score(candidate: "workbench.quickOpen", query: "workbench.quickOpen")
        let prefix = CommandPaletteScoring.score(candidate: "workbench.quickOpen", query: "work")
        let contains = CommandPaletteScoring.score(candidate: "workbench.quickOpen", query: "quick")
        let miss = CommandPaletteScoring.score(candidate: "workbench.quickOpen", query: "nope")

        #expect(exact > prefix)
        #expect(prefix > contains)
        #expect(contains > 0)
        #expect(miss == 0)
    }

    @Test func testGoToSymbolFallbackParsesSwift() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_goto_symbol_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        let content = """
        import Foundation

        class Foo {
            func bar() {}
        }

        struct Baz {}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let svc = WorkspaceSymbolSearchService(codebaseIndexProvider: { nil })
        let results = await svc.search(
            query: "Foo",
            projectRoot: tempRoot,
            currentFilePath: file.path,
            currentContent: content,
            currentLanguage: "swift",
            limit: 20
        )

        let foundFoo = results.first(where: { $0.name == "Foo" })
        #expect(foundFoo != nil)
        #expect(foundFoo?.relativePath == "a.swift")

        let lines = content.components(separatedBy: "\n")
        let expectedLine = (lines.firstIndex(where: { $0.contains("class Foo") }) ?? 0) + 1
        #expect(foundFoo?.line == expectedLine)
    }

    @Test func testWorkspaceNavigationIdentifierAtCursor() async throws {
        let text = "let fooBar = 1\nprint(fooBar)\n"
        let ns = text as NSString
        let cursor = ns.range(of: "fooBar").location + 2
        let ident = WorkspaceNavigationService.identifierAtCursor(in: text, cursor: cursor)
        #expect(ident == "fooBar")

        let cursorOnWhitespace = ns.range(of: "print").location - 1
        let none = WorkspaceNavigationService.identifierAtCursor(in: text, cursor: cursorOnWhitespace)
        #expect(none == nil)
    }

    @Test func testWorkspaceNavigationRenameInCurrentBufferWholeWord() async throws {
        let content = "let foo = 1\nlet foobar = 2\nfoo = foo + 1\n"
        let result = try WorkspaceNavigationService.renameInCurrentBuffer(content: content, identifier: "foo", newName: "bar")
        #expect(result.replacements == 3)
        #expect(result.updated.contains("let bar = 1"))
        #expect(result.updated.contains("let foobar = 2"))
        #expect(result.updated.contains("bar = bar + 1"))
    }

    @Test func testWorkspaceNavigationRenameRejectsInvalidIdentifier() async throws {
        do {
            _ = try WorkspaceNavigationService.renameInCurrentBuffer(content: "let foo = 1", identifier: "foo", newName: "1bad")
            #expect(false, "Expected rename to throw for invalid identifier")
        } catch {
            #expect(error.localizedDescription.lowercased().contains("invalid identifier"))
        }
    }

    @Test func testDiagnosticsParserParsesXcodebuildErrorLine() async throws {
        let line = "/Users/me/Project/Foo.swift:42:13: error: Cannot find 'Bar' in scope"
        let parsedDiagnostic = DiagnosticsParser.parseXcodebuildLine(line)
        #expect(parsedDiagnostic != nil)
        #expect(parsedDiagnostic?.relativePath == "/Users/me/Project/Foo.swift")
        #expect(parsedDiagnostic?.line == 42)
        #expect(parsedDiagnostic?.column == 13)
        #expect(parsedDiagnostic?.severity == .error)
        #expect(parsedDiagnostic?.message.contains("Cannot find") == true)
    }

    @Test func testCodeFoldingRangeFinderFindsBraceFoldRangeAtCursor() async throws {
        let content = """
        func foo() {
            print(\"a\")
            if true {
                print(\"b\")
            }
        }
        """

        let ns = content as NSString
        let cursor = ns.range(of: "print(\"b\")").location
        let foldRange = CodeFoldingRangeFinder.foldRange(at: cursor, in: content)
        #expect(foldRange != nil)
        #expect(foldRange?.length ?? 0 > 0)

        // The smallest containing fold should be the inner `if` block, not the outer function.
        let foldedText = ns.substring(with: foldRange!)
        #expect(foldedText.contains("print(\"b\")"))
        #expect(!foldedText.contains("print(\"a\")"))
    }

    @Test func testCodeFoldingRangeFinderReturnsAllFoldRanges() async throws {
        let content = """
        struct A {
            func foo() {
                print(\"x\")
            }
        }
        """

        let ranges = CodeFoldingRangeFinder.allFoldRanges(in: content)
        #expect(ranges.count == 2)
    }

    @Test func testMultiCursorUtilitiesNextOccurrence() async throws {
        let text = "foo bar foo baz foo"
        let r1 = MultiCursorUtilities.nextOccurrenceRange(text: text, needle: "foo", fromIndex: 0)
        #expect(r1?.location == 0)

        let r2 = MultiCursorUtilities.nextOccurrenceRange(text: text, needle: "foo", fromIndex: 1)
        #expect(r2?.location == 8)
    }

    @Test func testMultiCursorUtilitiesCaretMoveVertical() async throws {
        let text = "abc\n012345\nxyz\n"
        // caret at column 2 of line 2 (0-based) => '2'
        let ns = text as NSString
        let line2Start = ns.range(of: "012345").location
        let caret = line2Start + 2

        let up = MultiCursorUtilities.caretMovedVertically(text: text, caret: caret, direction: .up)
        #expect(up == 2)

        let down = MultiCursorUtilities.caretMovedVertically(text: text, caret: caret, direction: .down)
        let line3Start = ns.range(of: "xyz").location
        #expect(down == line3Start + 2)
    }

    @Test func testEditorAIContextBuilderPrefersSelection() async throws {
        let buffer = "let a = 1\nlet b = 2\n"
        let ns = buffer as NSString
        let selection = ns.range(of: "let b = 2")
        let ctx = EditorAIContextBuilder.build(
            filePath: "/tmp/test.swift",
            language: "swift",
            buffer: buffer,
            selection: selection
        )

        #expect(ctx.contains("File: /tmp/test.swift"))
        #expect(ctx.contains("Language: swift"))
        #expect(ctx.contains("Selected Code:"))
        #expect(ctx.contains("let b = 2"))
        #expect(!ctx.contains("Buffer:\n\n\(buffer)"))
    }

    @Test func testCodeSelectionContext() async throws {
        let context = CodeSelectionContext()

        #expect(context.selectedText.isEmpty, "Selected text should be empty initially")
        #expect(context.selectedRange == nil, "Selected range should be nil initially")

        context.selectedText = "test selection"
        context.selectedRange = NSRange(location: 0, length: 13)

        #expect(context.selectedText == "test selection", "Selected text should be updated")
        #expect(context.selectedRange?.location == 0, "Selected range location should be set")
        #expect(context.selectedRange?.length == 13, "Selected range length should be set")
    }
}
