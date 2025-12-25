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
        
        #expect(appState.selectedFile == nil, "Selected file should be nil initially")
        #expect(appState.editorContent.isEmpty, "Editor content should be empty initially")
        #expect(appState.editorLanguage == "swift", "Default language should be swift")
        #expect(appState.isDirty == false, "Should not be dirty initially")
        #expect(appState.lastError == nil, "Should have no errors initially")

        // Workspace can be nil until the user explicitly selects a folder.
        if let dir = appState.currentDirectory {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) && isDir.boolValue, "If set, currentDirectory must exist and be a directory")
        }
    }

    @Test func testLanguageDetection() async throws {
        #expect(AppState.languageForFileExtension("swift") == "swift", "Swift files should detect as swift")
        #expect(AppState.languageForFileExtension("js") == "javascript", "JS files should detect as javascript")
        #expect(AppState.languageForFileExtension("jsx") == "javascript", "JSX files should detect as javascript")
        #expect(AppState.languageForFileExtension("ts") == "typescript", "TS files should detect as typescript")
        #expect(AppState.languageForFileExtension("tsx") == "typescript", "TSX files should detect as typescript")
        #expect(AppState.languageForFileExtension("py") == "python", "Python files should detect as python")
        #expect(AppState.languageForFileExtension("html") == "html", "HTML files should detect as html")
        #expect(AppState.languageForFileExtension("css") == "css", "CSS files should detect as css")
        #expect(AppState.languageForFileExtension("json") == "json", "JSON files should detect as json")
        #expect(AppState.languageForFileExtension("unknown") == "text", "Unknown files should default to text")
        #expect(AppState.languageForFileExtension("") == "text", "Empty extension should default to text")
    }

    @Test func testNewFileFunctionality() async throws {
        let appState = DependencyContainer.shared.makeAppState()
        
        appState.editorContent = "some content"
        // appState.selectedFile and .isDirty are read-only
        
        appState.newFile()
        
        #expect(appState.selectedFile == nil, "Selected file should be nil after new")
        #expect(appState.editorContent.isEmpty, "Editor content should be empty after new")
        #expect(appState.isDirty == false, "Should not be dirty after new")
        #expect(appState.lastError == nil, "Should have no errors after new")
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
