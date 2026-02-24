import Testing
import Foundation
@testable import osx_ide

@MainActor
struct IndexAndToolsTests {

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

        let patterns = IndexExcludePatternManager.loadExcludePatterns(projectRoot: tempRoot, defaultPatterns: IndexConfiguration.default.excludePatterns)
        let excludeFile = tempRoot.appendingPathComponent(".ide").appendingPathComponent("index_exclude")
        #expect(FileManager.default.fileExists(atPath: excludeFile.path), "Expected .ide/index_exclude to be created")

        let files = IndexFileEnumerator.enumerateProjectFiles(rootURL: tempRoot, excludePatterns: patterns)

        #expect(
            files.contains(where: { $0.standardizedFileURL.path == srcFile.standardizedFileURL.path }),
            "Expected src file to be enumerated"
        )
        #expect(
            !files.contains(where: { $0.path.contains("node_modules") }),
            "Expected node_modules tree to be excluded from enumeration"
        )
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

        let patterns = IndexExcludePatternManager.loadExcludePatterns(projectRoot: tempRoot, defaultPatterns: IndexConfiguration.default.excludePatterns)
        let files = IndexFileEnumerator.enumerateProjectFiles(rootURL: tempRoot, excludePatterns: patterns)

        #expect(
            files.contains(where: { $0.standardizedFileURL.path == tsxFile.standardizedFileURL.path }),
            "Expected .tsx file to be enumerated"
        )
    }

    @Test func testIndexReadFileFallsBackToDiskWhenNotIndexed() async throws {
        struct LocalMockAIService: AIService, @unchecked Sendable {
            func sendMessage(
                _ request: AIServiceMessageWithProjectRootRequest
            ) async throws -> AIServiceResponse {
                _ = request
                return AIServiceResponse(content: nil, toolCalls: nil)
            }

            func sendMessage(
                _ request: AIServiceHistoryRequest
            ) async throws -> AIServiceResponse {
                _ = request
                return AIServiceResponse(content: nil, toolCalls: nil)
            }
            func explainCode(_: String) async throws -> String { "" }
            func refactorCode(_: String, instructions _: String) async throws -> String { "" }
            func generateCode(_: String) async throws -> String { "" }
            func fixCode(_: String, error _: String) async throws -> String { "" }
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

    @Test func testFileOperationsWithCleanup() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).swift")

        // Track file for cleanup
        TestSupport.testFiles.append(testFile)

        // Create test file
        let testContent = "func testFunction() { print(\"Test\") }"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: testFile.path), "Test file should be created")

        // Clean up test file
        try? FileManager.default.removeItem(at: testFile)
        TestSupport.testFiles.removeAll { $0 == testFile }

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

        let writeFilesTool = WriteFilesTool(fileSystemService: fileSystemService, pathValidator: validator, eventBus: EventBus())
        _ = try await writeFilesTool.execute(arguments: ToolArguments([
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
        ]))

        let registerURL = tempRoot.appendingPathComponent("src/pages/Register.tsx")
        let buttonURL = tempRoot.appendingPathComponent("src/components/Button.tsx")

        #expect(FileManager.default.fileExists(atPath: registerURL.path), "Register.tsx should be written")
        #expect(FileManager.default.fileExists(atPath: buttonURL.path), "Button.tsx should be written")

        let registerContent = try fileSystemService.readFile(at: registerURL)
        #expect(registerContent.contains("function Register"), "Register.tsx content should match")

        let createFileTool = CreateFileTool(pathValidator: validator, eventBus: EventBus())
        _ = try await createFileTool.execute(arguments: ToolArguments([
            "path": "src/styles/app.css"
        ]))

        let cssURL = tempRoot.appendingPathComponent("src/styles/app.css")
        #expect(FileManager.default.fileExists(atPath: cssURL.path), "Nested create_file should create parent directories")
        let cssContent = try fileSystemService.readFile(at: cssURL)
        #expect(cssContent.isEmpty, "create_file should create an empty file")
    }

    @Test func testReplaceInFileThrowsWhenOldTextDoesNotMatch() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_replace_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("config.txt")
        try "version=1.0\nname=current\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = ReplaceInFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": "config.txt",
                "old_text": "name=missing",
                "new_text": "name=new"
            ]))
            #expect(false, "Expected replace_in_file to throw when old_text does not match")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("could not find old_text"))
        }
    }

    @Test func testCreateFileThrowsWhenPathAlreadyExists() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_create_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("existing.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = CreateFileTool(
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": "existing.txt"
            ]))
            #expect(false, "Expected create_file to throw when file already exists")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("already exists"))
        }
    }

    @Test func testReplaceInFileTreatsAlreadyAppliedStateAsNoOp() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_replace_noop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("config.txt")
        try "version=1.0\nname=new\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = ReplaceInFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        let result = try await tool.execute(arguments: ToolArguments([
            "path": "config.txt",
            "old_text": "name=old",
            "new_text": "name=new"
        ]))

        #expect(result.localizedCaseInsensitiveContains("No-op"))
        let persisted = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(persisted.contains("name=new"))
    }

    @Test func testDeleteFileThrowsWhenPathDoesNotExist() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_delete_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let tool = DeleteFileTool(
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": "missing.txt"
            ]))
            #expect(false, "Expected delete_file to throw when file does not exist")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("does not exist"))
        }
    }
}
