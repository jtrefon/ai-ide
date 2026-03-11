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
        let cssDirectoryURL = tempRoot.appendingPathComponent("src/styles", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: cssDirectoryURL.path), "Nested create_file should prepare parent directories")
        #expect(!FileManager.default.fileExists(atPath: cssURL.path), "create_file should not materialize an empty file before content is written")
    }

    @Test func testFileToolsNormalizeProjectPseudoRootPaths() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_project_pseudoroot_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileSystemService = FileSystemService()
        let validator = PathValidator(projectRoot: tempRoot)
        let eventBus = EventBus()

        let writeFileTool = WriteFileTool(
            fileSystemService: fileSystemService,
            pathValidator: validator,
            eventBus: eventBus
        )
        _ = try await writeFileTool.execute(arguments: ToolArguments([
            "path": "/project/index.html",
            "content": "<html></html>"
        ]))

        let rootIndexURL = tempRoot.appendingPathComponent("index.html")
        let nestedProjectIndexURL = tempRoot.appendingPathComponent("project/index.html")
        #expect(FileManager.default.fileExists(atPath: rootIndexURL.path), "Pseudo-root /project/index.html should resolve to the real project root")
        #expect(!FileManager.default.fileExists(atPath: nestedProjectIndexURL.path), "Pseudo-root /project/index.html must not create a nested project directory")

        let createFileTool = CreateFileTool(pathValidator: validator, eventBus: eventBus)
        _ = try await createFileTool.execute(arguments: ToolArguments([
            "path": "project/src/App.jsx"
        ]))

        let appDirectoryURL = tempRoot.appendingPathComponent("src", isDirectory: true)
        let nestedProjectAppURL = tempRoot.appendingPathComponent("project/src/App.jsx")
        #expect(FileManager.default.fileExists(atPath: appDirectoryURL.path), "project/src/App.jsx should resolve to src/App.jsx under the real root")
        #expect(!FileManager.default.fileExists(atPath: nestedProjectAppURL.path), "project/src/App.jsx must not materialize a nested project directory")
    }

    @Test func testListFilesReturnsEmptyForMissingProjectRelativeDirectory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_missing_dir_list_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let validator = PathValidator(projectRoot: tempRoot)
        let listFilesTool = ListFilesTool(pathValidator: validator)

        let result = try await listFilesTool.execute(arguments: ToolArguments([
            "path": "src"
        ]))

        #expect(result.isEmpty, "Missing project-relative directories should return an empty listing instead of failing")
    }

    @Test func testCreateFileReturnsInformationalMessageWhenPathAlreadyExists() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_existing_create_file_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let existingURL = tempRoot.appendingPathComponent("package.json")
        try "{}".write(to: existingURL, atomically: true, encoding: .utf8)

        let createFileTool = CreateFileTool(pathValidator: PathValidator(projectRoot: tempRoot), eventBus: EventBus())
        let result = try await createFileTool.execute(arguments: ToolArguments([
            "path": "package.json"
        ]))

        #expect(result.contains("already exists"), "Expected create_file to guide the model toward write_file instead of failing")
    }

    @Test func testCreateFileWritesProvidedContentImmediately() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_create_file_with_content_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let createFileTool = CreateFileTool(pathValidator: PathValidator(projectRoot: tempRoot), eventBus: EventBus())
        let result = try await createFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "content": "export default function App() { return null }\n"
        ]))

        let createdURL = tempRoot.appendingPathComponent("src/App.jsx")
        let persisted = try String(contentsOf: createdURL, encoding: .utf8)

        #expect(result.localizedCaseInsensitiveContains("wrote provided content"))
        #expect(persisted.contains("function App"))
    }

    @Test func testCreateFileTreatsMatchingExistingContentAsNoOp() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_create_file_content_noop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let existingURL = tempRoot.appendingPathComponent("package.json")
        try "{}\n".write(to: existingURL, atomically: true, encoding: .utf8)

        let createFileTool = CreateFileTool(pathValidator: PathValidator(projectRoot: tempRoot), eventBus: EventBus())
        let result = try await createFileTool.execute(arguments: ToolArguments([
            "path": "package.json",
            "content": "{}\n"
        ]))

        #expect(result.localizedCaseInsensitiveContains("already matches"))
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

    @Test func testWriteFileBlocksBlindFullOverwriteOfExistingFile() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_blind_overwrite_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("server.js")
        try "const app = createServer();\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": "server.js",
                "content": "import express from 'express'\nconst app = express()\n",
                "_conversation_id": "blind-overwrite-conversation"
            ]))
            #expect(false, "Expected blind overwrite of existing file to be rejected")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("refused full-file overwrite"))
        }
    }

    @Test func testWriteFileAllowsFullRewriteAfterReadInSameConversation() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_read_then_rewrite_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("server.js")
        try "const app = createServer();\napp.listen(3000);\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let conversationId = "read-then-rewrite-conversation"
        let readTool = ReadFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot)
        )
        _ = try await readTool.execute(arguments: ToolArguments([
            "path": "server.js",
            "_conversation_id": conversationId
        ]))

        let writeTool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )
        _ = try await writeTool.execute(arguments: ToolArguments([
            "path": "server.js",
            "content": "import express from 'express'\nconst app = express()\napp.listen(3000)\n",
            "_conversation_id": conversationId
        ]))

        let rewrittenContent = try String(contentsOf: fileURL)
        #expect(rewrittenContent.contains("import express from 'express'"), "Expected full rewrite to succeed after a same-conversation read")
    }

    @Test func testWriteFileReturnsNoOpWhenContentAlreadyMatches() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_write_file_noop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("index.html")
        let existingContent = "<!DOCTYPE html>\n<html></html>\n"
        try existingContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        let result = try await tool.execute(arguments: ToolArguments([
            "path": "index.html",
            "content": existingContent,
            "_conversation_id": "same-content-noop"
        ]))

        #expect(result.localizedCaseInsensitiveContains("no-op"))
    }

    @Test func testWriteFileRejectsAbsolutePathFromSiblingTemporaryRoot() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_path_root_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let siblingRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_path_root_\(UUID().uuidString)_sibling")
        try FileManager.default.createDirectory(at: siblingRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: siblingRoot) }

        let siblingFile = siblingRoot.appendingPathComponent("src/math.ts")
        let tool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": siblingFile.path,
                "content": "export function add(a: number, b: number): number { return a + b }"
            ]))
            #expect(false, "Expected sibling absolute path to be rejected as outside project root")
        } catch {
            #expect(error.localizedDescription.localizedCaseInsensitiveContains("outside the project directory"))
        }

        #expect(!FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(String(siblingFile.path.dropFirst())).path))
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
