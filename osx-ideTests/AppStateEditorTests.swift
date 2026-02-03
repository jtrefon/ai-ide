import Testing
import Foundation
import AppKit
import SwiftUI
@testable import osx_ide

@MainActor
struct AppStateEditorTests {

    @Test func testAppStateInitialization() async throws {
        let appState = DependencyContainer().makeAppState()

        #expect(appState.fileEditor.selectedFile == nil, "Selected file should be nil initially")
        #expect(appState.fileEditor.editorContent.isEmpty, "Editor content should be empty initially")
        #expect(appState.fileEditor.editorLanguage == "swift", "Default language should be swift")
        #expect(appState.fileEditor.isDirty == false, "Should not be dirty initially")
        #expect(appState.lastError == nil, "Should have no errors initially")

        // Workspace can be nil until the user explicitly selects a folder.
        if let dir = appState.workspace.currentDirectory {
            var isDir: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue,
                "If set, currentDirectory must exist and be a directory"
            )
        }
    }

    @Test func testLanguageDetection() async throws {
        #expect(
            FileEditorStateManager.languageForFileExtension("swift") == "swift",
            "Swift files should detect as swift"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("js") == "javascript",
            "JS files should detect as javascript"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("jsx") == "jsx",
            "JSX files should detect as jsx"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("ts") == "typescript",
            "TS files should detect as typescript"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("tsx") == "tsx",
            "TSX files should detect as tsx"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("py") == "python",
            "Python files should detect as python"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("html") == "html",
            "HTML files should detect as html"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("css") == "css",
            "CSS files should detect as css"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("json") == "json",
            "JSON files should detect as json"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("unknown") == "text",
            "Unknown files should default to text"
        )
        #expect(
            FileEditorStateManager.languageForFileExtension("") == "text",
            "Empty extension should default to text"
        )
    }

    @Test func testNewFileFunctionality() async throws {
        let appState = DependencyContainer().makeAppState()

        appState.fileEditor.editorContent = "some content"
        // appState.fileEditor.selectedFile and .isDirty are read-only

        appState.fileEditor.newFile()

        #expect(appState.fileEditor.selectedFile == nil, "Selected file should be nil after new")
        #expect(appState.fileEditor.editorContent.isEmpty, "Editor content should be empty after new")
        #expect(appState.fileEditor.isDirty == false, "Should not be dirty after new")
        #expect(appState.lastError == nil, "Should have no errors after new")
    }

    @Test func testEditorTabsNoDuplicatesOnRepeatedOpen() async throws {
        let appState = DependencyContainer().makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_tabs_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        try "print(\"hello\")".write(to: file, atomically: true, encoding: .utf8)

        appState.fileEditor.loadFile(from: file)
        appState.fileEditor.loadFile(from: file)

        #expect(
            appState.fileEditor.tabs.count == 1,
            "Opening same file twice should not create duplicate tabs"
        )
        #expect(appState.fileEditor.selectedFile == file.path, "Expected selectedFile to be the opened file")
    }

    @Test func testOpenJSONFileSetsEditorLanguageToJSON() async throws {
        let appState = DependencyContainer().makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_open_json_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("data.json")
        try "{\"a\": 1, \"b\": true, \"c\": null}".write(to: file, atomically: true, encoding: .utf8)

        appState.fileEditor.loadFile(from: file)

        #expect(appState.fileEditor.selectedFile == file.path)
        #expect(
            appState.fileEditor.editorLanguage == "json",
            "Expected .json files to set editorLanguage=json"
        )
    }

    @Test func testSyntaxHighlighterJSONProducesMultipleColors() async throws {
        let code = """
        {
          \"key\": \"value\",
          \"number\": 123,
          \"bool\": true,
          \"nullVal\": null,
          \"arr\": [1, false],
          \"obj\": {\"nested\": false}
        }
        """

        let result = SyntaxHighlighter.shared.highlight(code, language: "json")
        let unique = TestSupport.uniqueForegroundColorCount(in: result)

        #expect(
            unique >= 4,
            "Expected json highlighting to apply multiple colors; got unique=\(unique)"
        )
    }

    @Test func testUntitledBufferAutoDetectsJSONLanguageOnPaste() async throws {
        let appState = DependencyContainer().makeAppState()

        appState.fileEditor.newFile()
        #expect(appState.fileEditor.selectedFile == nil)
        #expect(appState.fileEditor.editorLanguage == "swift")

        let pasted = """
        {
          \"key\": \"value\",
          \"n\": 1,
          \"b\": true,
          \"z\": null
        }
        """

        appState.fileEditor.editorContent = pasted
        #expect(
            appState.fileEditor.editorLanguage == "json",
            "Expected pasted JSON in untitled buffer to auto-switch editorLanguage to json"
        )
    }

    @Test func testEditorCloseActiveTabClearsStateWhenLastTab() async throws {
        let appState = DependencyContainer().makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_tabs_close_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let file = tempRoot.appendingPathComponent("a.swift")
        try "print(\"hello\")".write(to: file, atomically: true, encoding: .utf8)

        appState.fileEditor.loadFile(from: file)
        #expect(appState.fileEditor.tabs.count == 1)

        appState.fileEditor.closeActiveTab()

        #expect(appState.fileEditor.tabs.isEmpty, "Expected no tabs after closing last tab")
        #expect(
            appState.fileEditor.selectedFile == nil,
            "Expected selectedFile to be nil after closing last tab"
        )
    }

    @Test func testSplitEditorOpenTargetsFocusedPane() async throws {
        let appState = DependencyContainer().makeAppState()

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_split_focus_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileA = tempRoot.appendingPathComponent("a.swift")
        let fileB = tempRoot.appendingPathComponent("b.swift")
        try "print(\"a\")".write(to: fileA, atomically: true, encoding: .utf8)
        try "print(\"b\")".write(to: fileB, atomically: true, encoding: .utf8)

        appState.fileEditor.toggleSplit(axis: FileEditorStateManager.SplitAxis.vertical)
        appState.fileEditor.focus(FileEditorStateManager.PaneID.secondary)

        appState.fileEditor.loadFile(from: fileB)

        #expect(appState.fileEditor.isSplitEditor == true, "Expected split editor to be enabled")
        #expect(
            appState.fileEditor.secondaryPane.tabs.contains(where: { $0.filePath == fileB.path }),
            "Expected file to open in secondary pane"
        )
        #expect(
            !appState.fileEditor.primaryPane.tabs.contains(where: { $0.filePath == fileB.path }),
            "Expected file not to open in primary pane"
        )
    }
}
