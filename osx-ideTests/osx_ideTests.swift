//
//  osx_ideTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 25/08/2025.
//

import Testing
import Foundation
import AppKit
import SwiftUI
import Combine
@testable import osx_ide

@MainActor
struct osx_ideTests {
    private static var testFiles: [URL] = []
    
    @Test func testAppStateInitialization() async throws {
        let appState = DependencyContainer.shared.makeAppState()
        
        #expect(appState.fileEditor.selectedFile == nil, "Selected file should be nil initially")
        #expect(appState.fileEditor.editorContent.isEmpty, "Editor content should be empty initially")
        #expect(appState.fileEditor.editorLanguage == "swift", "Default language should be swift")
        #expect(appState.fileEditor.isDirty == false, "Should not be dirty initially")
        #expect(appState.lastError == nil, "Should have no errors initially")

        // Workspace can be nil until the user explicitly selects a folder.
        if let dir = appState.workspace.currentDirectory {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue, "If set, currentDirectory must exist and be a directory")
        }
    }

    @Test func testLanguageDetection() async throws {
        #expect(FileEditorStateManager.languageForFileExtension("swift") == "swift", "Swift files should detect as swift")
        #expect(FileEditorStateManager.languageForFileExtension("js") == "javascript", "JS files should detect as javascript")
        #expect(FileEditorStateManager.languageForFileExtension("jsx") == "javascript", "JSX files should detect as javascript")
        #expect(FileEditorStateManager.languageForFileExtension("ts") == "typescript", "TS files should detect as typescript")
        #expect(FileEditorStateManager.languageForFileExtension("tsx") == "typescript", "TSX files should detect as typescript")
        #expect(FileEditorStateManager.languageForFileExtension("py") == "python", "Python files should detect as python")
        #expect(FileEditorStateManager.languageForFileExtension("html") == "html", "HTML files should detect as html")
        #expect(FileEditorStateManager.languageForFileExtension("css") == "css", "CSS files should detect as css")
        #expect(FileEditorStateManager.languageForFileExtension("json") == "json", "JSON files should detect as json")
        #expect(FileEditorStateManager.languageForFileExtension("unknown") == "text", "Unknown files should default to text")
        #expect(FileEditorStateManager.languageForFileExtension("") == "text", "Empty extension should default to text")
    }

    @Test func testNewFileFunctionality() async throws {
        let appState = DependencyContainer.shared.makeAppState()
        
        appState.fileEditor.editorContent = "some content"
        // appState.fileEditor.selectedFile and .isDirty are read-only
        
        appState.fileEditor.newFile()
        
        #expect(appState.fileEditor.selectedFile == nil, "Selected file should be nil after new")
        #expect(appState.fileEditor.editorContent.isEmpty, "Editor content should be empty after new")
        #expect(appState.fileEditor.isDirty == false, "Should not be dirty after new")
        #expect(appState.lastError == nil, "Should have no errors after new")
    }

    @Test func testEditorTabsNoDuplicatesOnRepeatedOpen() async throws {
        let appState = DependencyContainer.shared.makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_tabs_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        try "print(\"hello\")".write(to: file, atomically: true, encoding: .utf8)

        appState.fileEditor.loadFile(from: file)
        appState.fileEditor.loadFile(from: file)

        #expect(appState.fileEditor.tabs.count == 1, "Opening same file twice should not create duplicate tabs")
        #expect(appState.fileEditor.selectedFile == file.path, "Expected selectedFile to be the opened file")
    }

    @Test func testEditorCloseActiveTabClearsStateWhenLastTab() async throws {
        let appState = DependencyContainer.shared.makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_tabs_close_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        try "print(\"hello\")".write(to: file, atomically: true, encoding: .utf8)

        appState.fileEditor.loadFile(from: file)
        #expect(appState.fileEditor.tabs.count == 1)

        appState.fileEditor.closeActiveTab()

        #expect(appState.fileEditor.tabs.isEmpty, "Expected no tabs after closing last tab")
        #expect(appState.fileEditor.selectedFile == nil, "Expected selectedFile to be nil after closing last tab")
    }

    @Test func testSplitEditorOpenTargetsFocusedPane() async throws {
        let appState = DependencyContainer.shared.makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_split_focus_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileA = tempRoot.appendingPathComponent("a.swift")
        let fileB = tempRoot.appendingPathComponent("b.swift")
        try "print(\"a\")".write(to: fileA, atomically: true, encoding: .utf8)
        try "print(\"b\")".write(to: fileB, atomically: true, encoding: .utf8)

        appState.fileEditor.toggleSplit(axis: .vertical)
        appState.fileEditor.focus(.secondary)

        appState.fileEditor.loadFile(from: fileB)

        #expect(appState.fileEditor.isSplitEditor == true, "Expected split editor to be enabled")
        #expect(appState.fileEditor.secondaryPane.tabs.contains(where: { $0.filePath == fileB.path }), "Expected file to open in secondary pane")
        #expect(!appState.fileEditor.primaryPane.tabs.contains(where: { $0.filePath == fileB.path }), "Expected file not to open in primary pane")
    }

    @Test func testQuickOpenParseQuerySupportsLineSuffix() async throws {
        let parsed1 = QuickOpenOverlayView.parseQuery("Sources/Foo.swift:12")
        #expect(parsed1.fileQuery == "Sources/Foo.swift")
        #expect(parsed1.line == 12)

        let parsed2 = QuickOpenOverlayView.parseQuery("Foo.swift")
        #expect(parsed2.fileQuery == "Foo.swift")
        #expect(parsed2.line == nil)
    }

    @Test func testWorkspaceSearchParseIndexedMatchLine() async throws {
        let m = WorkspaceSearchService.parseIndexedMatchLine("src/main.swift:42: print(\"hi\")")
        #expect(m?.relativePath == "src/main.swift")
        #expect(m?.line == 42)
        #expect(m?.snippet == "print(\"hi\")")
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
        let results = svc.search(
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

    @Test func testSyntaxHighlighter() async throws {
        let highlighter = SyntaxHighlighter.shared
        
        // Test Swift highlighting
        let swiftCode = """
        import Foundation
        
        class MyClass {
            let name: String
            
            init(name: String) {
                self.name = name
            }
            
            func greet() -> String {
                return "Hello, " + name + "!"
            }
        }
        """
        
        let swiftResult = highlighter.highlight(swiftCode, language: "swift")
        #expect(!swiftResult.string.isEmpty, "Highlighted result should not be empty")
        #expect(swiftResult.string == swiftCode, "Result should contain original code")
        
        // Verify that highlighting produced at least one non-default foreground color.
        var foundAnyHighlight = false
        swiftResult.enumerateAttributes(in: NSRange(location: 0, length: swiftResult.length), options: []) { attrs, _, _ in
            if let color = attrs[.foregroundColor] as? NSColor, color != NSColor.labelColor {
                foundAnyHighlight = true
            }
        }
        #expect(foundAnyHighlight, "Expected at least one highlight to be applied")
        
        // Test Python highlighting (should still return plain text with base styling)
        let pythonCode = """
        def hello_world():
            name = "World"
            print(f"Hello, {name}!")
            
        if __name__ == "__main__":
            hello_world()
        """
        
        let pythonResult = highlighter.highlight(pythonCode, language: "python")
        #expect(!pythonResult.string.isEmpty, "Python result should not be empty")
        #expect(pythonResult.string == pythonCode, "Python result should contain original code")
        
        // Test JavaScript highlighting (should still return plain text with base styling)
        let jsCode = """
        function greet(name) {
            return `Hello, ${name}!`;
        }
        
        const message = greet("World");
        console.log(message);
        """
        
        let jsResult = highlighter.highlight(jsCode, language: "javascript")
        #expect(!jsResult.string.isEmpty, "JavaScript result should not be empty")
        #expect(jsResult.string == jsCode, "JavaScript result should contain original code")
        
        // Test fallback for unknown language
        let unknownCode = "just plain text"
        let unknownResult = highlighter.highlight(unknownCode, language: "unknown")
        #expect(!unknownResult.string.isEmpty, "Unknown result should not be empty")
        #expect(unknownResult.string == unknownCode, "Unknown result should contain original code")
    }
    
    @Test func testHighlightingPerformance() async throws {
        let highlighter = SyntaxHighlighter.shared
        
        // Generate a large code sample
        var largeCode = """
        import Foundation
        
        class LargeClass {
        """
        
        for i in 0..<100 {
            largeCode += """
            
            func method\(i)() -> Int {
                return \(i)
            }
            """
        }
        
        largeCode += """
        }
        """
        
        // Measure highlighting performance
        let startTime = ContinuousClock.now
        _ = highlighter.highlight(largeCode, language: "swift")
        let endTime = ContinuousClock.now
        
        let duration = startTime.duration(to: endTime)
        #expect(duration < .seconds(1), "Highlighting should complete within 1 second")
    }

    @Test func testIndexExcludesSkipNodeModules() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_index_excludes_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let nodeModulesFile = tempRoot
            .appendingPathComponent("node_modules")
            .appendingPathComponent("somepkg")
            .appendingPathComponent("index.js")
        try FileManager.default.createDirectory(at: nodeModulesFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try "console.log('x')\n".write(to: nodeModulesFile, atomically: true, encoding: .utf8)

        let srcFile = tempRoot
            .appendingPathComponent("src")
            .appendingPathComponent("main.ts")
        try FileManager.default.createDirectory(at: srcFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try "export const x = 1\n".write(to: srcFile, atomically: true, encoding: .utf8)

        let patterns = IndexCoordinator.loadExcludePatterns(projectRoot: tempRoot, defaultPatterns: IndexConfiguration.default.excludePatterns)
        let excludeFile = tempRoot.appendingPathComponent(".ide").appendingPathComponent("index_exclude")
        #expect(FileManager.default.fileExists(atPath: excludeFile.path), "Expected .ide/index_exclude to be created")

        let files = IndexCoordinator.enumerateProjectFiles(rootURL: tempRoot, excludePatterns: patterns)

        #expect(files.contains(where: { $0.standardizedFileURL.path == srcFile.standardizedFileURL.path }), "Expected src file to be enumerated")
        #expect(!files.contains(where: { $0.path.contains("node_modules") }), "Expected node_modules tree to be excluded from enumeration")
    }

    @Test func testIndexEnumeratesTSX() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_index_tsx_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let tsxFile = tempRoot
            .appendingPathComponent("src")
            .appendingPathComponent("RegistrationPage.tsx")
        try FileManager.default.createDirectory(at: tsxFile.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try "export default function RegistrationPage() { return null }\n".write(to: tsxFile, atomically: true, encoding: .utf8)

        let patterns = IndexCoordinator.loadExcludePatterns(projectRoot: tempRoot, defaultPatterns: IndexConfiguration.default.excludePatterns)
        let files = IndexCoordinator.enumerateProjectFiles(rootURL: tempRoot, excludePatterns: patterns)

        #expect(files.contains(where: { $0.standardizedFileURL.path == tsxFile.standardizedFileURL.path }), "Expected .tsx file to be enumerated")
    }

    @Test func testIndexReadFileFallsBackToDiskWhenNotIndexed() async throws {
        struct LocalMockAIService: AIService, @unchecked Sendable {
            func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?) async throws -> AIServiceResponse { AIServiceResponse(content: nil, toolCalls: nil) }
            func sendMessage(_ message: String, context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse { AIServiceResponse(content: nil, toolCalls: nil) }
            func sendMessage(_ messages: [ChatMessage], context: String?, tools: [AITool]?, mode: AIMode?, projectRoot: URL?) async throws -> AIServiceResponse { AIServiceResponse(content: nil, toolCalls: nil) }
            func explainCode(_ code: String) async throws -> String { "" }
            func refactorCode(_ code: String, instructions: String) async throws -> String { "" }
            func generateCode(_ prompt: String) async throws -> String { "" }
            func fixCode(_ code: String, error: String) async throws -> String { "" }
        }

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_index_read_fallback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("src").appendingPathComponent("NewFile.tsx")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try "line1\nline2\n".write(to: file, atomically: true, encoding: .utf8)

        let index = try CodebaseIndex(eventBus: EventBus(), projectRoot: tempRoot, aiService: LocalMockAIService())

        // File is on disk but not in DB yet; should still be readable.
        let output = try index.readIndexedFile(path: "src/NewFile.tsx", startLine: 1, endLine: 2)
        #expect(output.contains("1 | line1"), "Expected line-numbered output")
        #expect(output.contains("2 | line2"), "Expected line-numbered output")
    }

    @Test func testErrorHandling() async throws {
        let appState = DependencyContainer.shared.makeAppState()
        
        appState.lastError = "Test error"
        
        #expect(appState.lastError?.contains("Test error") == true, "Error should be stored")
        
        appState.lastError = nil
        #expect(appState.lastError == nil, "Error should be clearable")
    }

    @Test func testWorkspaceServiceRenamePublishesEventAndMovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let workspaceService = WorkspaceService(errorManager: errorManager, eventBus: eventBus)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_workspace_rename_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        workspaceService.currentDirectory = tempRoot

        let file = tempRoot.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        var capturedOld: URL?
        var capturedNew: URL?
        let cancellable = eventBus.subscribe(to: FileRenamedEvent.self) { event in
            capturedOld = event.oldUrl
            capturedNew = event.newUrl
        }
        _ = cancellable

        let newURL = workspaceService.renameItem(at: file, to: "b.txt")
        #expect(newURL != nil, "Expected rename to return new URL")

        #expect(!FileManager.default.fileExists(atPath: file.path), "Expected old path to be gone")
        #expect(FileManager.default.fileExists(atPath: newURL!.path), "Expected new path to exist")

        #expect(capturedOld?.standardizedFileURL.path == file.standardizedFileURL.path, "Expected event oldUrl to match")
        #expect(capturedNew?.standardizedFileURL.path == newURL!.standardizedFileURL.path, "Expected event newUrl to match")
    }

    @Test func testWorkspaceServiceDeletePublishesEventAndRemovesFile() async throws {
        let errorManager = ErrorManager()
        let eventBus = EventBus()
        let workspaceService = WorkspaceService(errorManager: errorManager, eventBus: eventBus)

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_workspace_delete_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        workspaceService.currentDirectory = tempRoot

        let file = tempRoot.appendingPathComponent("delete_me.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        var capturedDeleted: URL?
        let cancellable = eventBus.subscribe(to: FileDeletedEvent.self) { event in
            capturedDeleted = event.url
        }
        _ = cancellable

        workspaceService.deleteItem(at: file)

        #expect(!FileManager.default.fileExists(atPath: file.path), "Expected file to be removed from original location")
        #expect(capturedDeleted?.standardizedFileURL.path == file.standardizedFileURL.path, "Expected delete event to reference the removed file")
    }
    
    @Test func testFileOperationsWithCleanup() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).swift")
        
        // Track file for cleanup
        Self.testFiles.append(testFile)
        
        // Create test file
        let testContent = "func testFunction() { print(\"Test\") }"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)
        
        #expect(FileManager.default.fileExists(atPath: testFile.path), "Test file should be created")
        
        // Clean up test file
        try? FileManager.default.removeItem(at: testFile)
        Self.testFiles.removeAll { $0 == testFile }
        
        #expect(!FileManager.default.fileExists(atPath: testFile.path), "Test file should be cleaned up")
    }

    @Test func testFileToolsSupportNestedPaths() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_file_tools_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileSystemService = FileSystemService()
        let validator = PathValidator(projectRoot: tempRoot)

        let writeFilesTool = WriteFilesTool(fileSystemService: fileSystemService, pathValidator: validator)
        _ = try await writeFilesTool.execute(arguments: [
            "files": [
                [
                    "path": "src/pages/Register.tsx",
                    "content": "export default function Register() { return null }\n"
                ],
                [
                    "path": "src/components/Button.tsx",
                    "content": "export function Button() { return null }\n"
                ]
            ]
        ])

        let registerURL = tempRoot.appendingPathComponent("src/pages/Register.tsx")
        let buttonURL = tempRoot.appendingPathComponent("src/components/Button.tsx")

        #expect(FileManager.default.fileExists(atPath: registerURL.path), "Register.tsx should be written")
        #expect(FileManager.default.fileExists(atPath: buttonURL.path), "Button.tsx should be written")

        let registerContent = try fileSystemService.readFile(at: registerURL)
        #expect(registerContent.contains("function Register"), "Register.tsx content should match")

        let createFileTool = CreateFileTool(pathValidator: validator)
        _ = try await createFileTool.execute(arguments: [
            "path": "src/styles/app.css"
        ])

        let cssURL = tempRoot.appendingPathComponent("src/styles/app.css")
        #expect(FileManager.default.fileExists(atPath: cssURL.path), "Nested create_file should create parent directories")
        let cssContent = try fileSystemService.readFile(at: cssURL)
        #expect(cssContent.isEmpty, "create_file should create an empty file")
    }
    
    // Cleanup method to remove any remaining test files
    static func cleanupTestFiles() {
        for file in testFiles {
            try? FileManager.default.removeItem(at: file)
        }
        testFiles.removeAll()
    }
}

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
