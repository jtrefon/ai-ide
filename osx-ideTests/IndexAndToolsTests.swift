import XCTest
import Foundation
@testable import osx_ide

@MainActor
final class IndexAndToolsTests: XCTestCase {

    func testIndexExcludesSkipNodeModules() async throws {
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
        let excludeFile = tempRoot.appendingPathComponent(AppConstantsFileSystem.projectDirName).appendingPathComponent("index_exclude")
        XCTAssertTrue(FileManager.default.fileExists(atPath: excludeFile.path), "Expected \(AppConstantsFileSystem.projectDirName)/index_exclude to be created")

        let files = IndexFileEnumerator.enumerateProjectFiles(rootURL: tempRoot, excludePatterns: patterns)

        XCTAssertTrue(
            files.contains(where: { $0.standardizedFileURL.path == srcFile.standardizedFileURL.path }),
            "Expected src file to be enumerated"
        )
        XCTAssertFalse(
            files.contains(where: { $0.path.contains("node_modules") }),
            "Expected node_modules tree to be excluded from enumeration"
        )
    }

    func testIndexEnumeratesTSX() async throws {
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

        XCTAssertTrue(
            files.contains(where: { $0.standardizedFileURL.path == tsxFile.standardizedFileURL.path }),
            "Expected .tsx file to be enumerated"
        )
    }

    func testIndexReadFileFallsBackToDiskWhenNotIndexed() async throws {
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
            func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
                try await sendMessage(request)
            }
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
        XCTAssertTrue(output.contains("1 | line1"), "Expected line-numbered output")
        XCTAssertTrue(output.contains("2 | line2"), "Expected line-numbered output")
    }

    func testFileOperationsWithCleanup() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_file_\(UUID().uuidString).swift")

        // Track file for cleanup
        TestSupport.testFiles.append(testFile)

        // Create test file
        let testContent = "func testFunction() { print(\"Test\") }"
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path), "Test file should be created")

        // Clean up test file
        try? FileManager.default.removeItem(at: testFile)
        TestSupport.testFiles.removeAll { $0 == testFile }

        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path), "Test file should be cleaned up")
    }

    func testFileToolsSupportNestedPaths() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_file_tools_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let fileSystemService = FileSystemService()
        let validator = PathValidator(projectRoot: tempRoot)
        let eventBus = EventBus()

        let writeFileTool1 = WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus)
        _ = try await writeFileTool1.execute(arguments: ToolArguments([
            "path": "src/pages/Register.tsx",
            "content": "export default function Register() { return null }\n",
            "_conversation_id": "file-tools-test"
        ]))

        let writeFileTool2 = WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus)
        _ = try await writeFileTool2.execute(arguments: ToolArguments([
            "path": "src/components/Button.tsx",
            "content": "export function Button() { return null }\n",
            "_conversation_id": "file-tools-test"
        ]))

        let registerURL = tempRoot.appendingPathComponent("src/pages/Register.tsx")
        let buttonURL = tempRoot.appendingPathComponent("src/components/Button.tsx")

        XCTAssertTrue(FileManager.default.fileExists(atPath: registerURL.path), "Register.tsx should be written")
        XCTAssertTrue(FileManager.default.fileExists(atPath: buttonURL.path), "Button.tsx should be written")

        let registerContent = try fileSystemService.readFile(at: registerURL)
        XCTAssertTrue(registerContent.contains("function Register"), "Register.tsx content should match")

        let writeFileTool3 = WriteFileTool(fileSystemService: fileSystemService, pathValidator: validator, eventBus: eventBus)
        _ = try await writeFileTool3.execute(arguments: ToolArguments([
            "path": "src/styles/app.css",
            "content": "",
            "_conversation_id": "file-tools-test"
        ]))

        let cssURL = tempRoot.appendingPathComponent("src/styles/app.css")
        let cssDirectoryURL = tempRoot.appendingPathComponent("src/styles", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cssDirectoryURL.path), "Nested write_file should prepare parent directories")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cssURL.path), "write_file should materialize the file")
    }

    func testFileToolsNormalizeProjectPseudoRootPaths() async throws {
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootIndexURL.path), "Pseudo-root /project/index.html should resolve to the real project root")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedProjectIndexURL.path), "Pseudo-root /project/index.html must not create a nested project directory")

        let writeFileTool3 = WriteFileTool(
            fileSystemService: fileSystemService,
            pathValidator: validator,
            eventBus: eventBus
        )
        _ = try await writeFileTool3.execute(arguments: ToolArguments([
            "path": "project/src/App.jsx",
            "content": "export default function App() { return null }",
            "_conversation_id": "file-tools-test"
        ]))

        let appDirectoryURL = tempRoot.appendingPathComponent("src", isDirectory: true)
        let nestedProjectAppURL = tempRoot.appendingPathComponent("project/src/App.jsx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appDirectoryURL.path), "project/src/App.jsx should resolve to src/App.jsx under the real root")
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedProjectAppURL.path), "project/src/App.jsx must not create a nested project directory")
    }

    func testListFilesReturnsEmptyForMissingProjectRelativeDirectory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_missing_dir_list_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let validator = PathValidator(projectRoot: tempRoot)
        let listFilesTool = ListFilesTool(pathValidator: validator)

        let result = try await listFilesTool.execute(arguments: ToolArguments([
            "path": "src"
        ]))

        XCTAssertTrue(result.isEmpty, "Missing project-relative directories should return an empty listing instead of failing")
    }

    func testWriteFileRejectsOverwritingExistingFile() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_existing_write_file_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let existingURL = tempRoot.appendingPathComponent("package.json")
        try "{}".write(to: existingURL, atomically: true, encoding: .utf8)

        let writeFileTool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )
        do {
            _ = try await writeFileTool.execute(arguments: ToolArguments([
                "path": "package.json",
                "content": "new content"
            ]))
            XCTFail("Expected write_file to reject overwriting existing files")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("Refused full-file overwrite"))
        }
    }

    func testWriteFileWritesContentImmediately() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_write_file_content_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let writeFileTool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )
        let result = try await writeFileTool.execute(arguments: ToolArguments([
            "path": "src/App.jsx",
            "content": "export default function App() { return null }\n"
        ]))

        let createdURL = tempRoot.appendingPathComponent("src/App.jsx")
        let persisted = try String(contentsOf: createdURL, encoding: .utf8)

        XCTAssertTrue(result.localizedCaseInsensitiveContains("successfully wrote"))
        XCTAssertTrue(persisted.contains("function App"))
    }

    func testWriteFileNoOpWithMatchingContent() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_write_file_noop2_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let existingURL = tempRoot.appendingPathComponent("package.json")
        try "{}\n".write(to: existingURL, atomically: true, encoding: .utf8)

        let writeFileTool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )
        let result = try await writeFileTool.execute(arguments: ToolArguments([
            "path": "package.json",
            "content": "{}\n",
            "_conversation_id": "write-file-noop-test2"
        ]))

        XCTAssertTrue(result.localizedCaseInsensitiveContains("already matches"))
    }

    func testReplaceInFileThrowsWhenOldTextDoesNotMatch() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_replace_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("config.txt")
        try "version=1.0\nname=current\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = PatchFileToolAdapter(projectRoot: tempRoot)

        let result = try await tool.execute(arguments: ToolArguments([
            "path": "config.txt",
            "start_line": 1,
            "end_line": 5,
            "new_content": "version=1.0\nname=new\n"
        ]))
        XCTAssertTrue(result.localizedCaseInsensitiveContains("Invalid"), "Expected patch_file to report invalid line range")
    }

    func testWriteFileThrowsWhenPathAlreadyExists() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_write_error_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("existing.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = WriteFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        do {
            _ = try await tool.execute(arguments: ToolArguments([
                "path": "existing.txt",
                "content": "world"
            ]))
            XCTFail("Expected write_file to throw when file already exists")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("Refused full-file overwrite"))
        }
    }

    func testWriteFileBlocksBlindFullOverwriteOfExistingFile() async throws {
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
            XCTFail("Expected blind overwrite of existing file to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("refused full-file overwrite"))
        }
    }

    func testWriteFileAllowsFullRewriteAfterReadInSameConversation() async throws {
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
        XCTAssertTrue(rewrittenContent.contains("import express from 'express'"), "Expected full rewrite to succeed after a same-conversation read")
    }

    func testWriteFileReturnsNoOpWhenContentAlreadyMatches() async throws {
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

        XCTAssertTrue(result.localizedCaseInsensitiveContains("no-op"))
    }

    func testWriteFileRejectsAbsolutePathFromSiblingTemporaryRoot() async throws {
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
            XCTFail("Expected sibling absolute path to be rejected as outside project root")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("outside the project directory"))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(String(siblingFile.path.dropFirst())).path))
    }

    func testReplaceInFileTreatsAlreadyAppliedStateAsNoOp() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("osx_ide_replace_noop_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fileURL = tempRoot.appendingPathComponent("config.txt")
        try "version=1.0\nname=new\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let tool = PatchFileToolAdapter(projectRoot: tempRoot)

        let result = try await tool.execute(arguments: ToolArguments([
            "path": "config.txt",
            "start_line": 2,
            "end_line": 2,
            "new_content": "name=new"
        ]))

        XCTAssertTrue(result.localizedCaseInsensitiveContains("success"))
        let persisted = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(persisted.contains("name=new"))
    }

    func testDeleteFileThrowsWhenPathDoesNotExist() async throws {
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
            XCTFail("Expected delete_file to throw when file does not exist")
        } catch {
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("does not exist"))
        }
    }
}
