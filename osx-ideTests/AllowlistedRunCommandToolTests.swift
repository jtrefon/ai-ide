import XCTest
import SwiftUI
import Combine
@testable import osx_ide

@MainActor
final class AllowlistedRunCommandToolTests: XCTestCase {
    private struct FakeRunCommandTool: AIToolProgressReporting {
        let name = "run_command"
        let description = "fake"
        var parameters: [String: Any] { ["type": "object", "properties": [:]] }

        func execute(arguments: ToolArguments) async throws -> String {
            let arguments = arguments.raw
            let cmd = (arguments["command"] as? String) ?? ""
            return "FAKE: \(cmd)"
        }

        func execute(
            arguments: ToolArguments,
            onProgress: @Sendable @escaping (String) -> Void
        ) async throws -> String {
            let arguments = arguments.raw
            let cmd = (arguments["command"] as? String) ?? ""
            onProgress("FAKE_PROGRESS")
            return "FAKE: \(cmd)"
        }
    }

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRejectsNonAllowlistedCommand() async {
        let tool = AllowlistedRunCommandTool(base: FakeRunCommandTool(), allowedPrefixes: ["echo ", "xcodebuild "])

        do {
            _ = try await tool.execute(arguments: ToolArguments(["command": "rm -rf /tmp/should_not_run"]))
            XCTFail("Expected non-allowlisted command to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.lowercased().contains("allowlisted"))
        }
    }

    func testAllowsEchoCommand() async throws {
        let tool = AllowlistedRunCommandTool(base: FakeRunCommandTool(), allowedPrefixes: ["echo "])

        let output = try await tool.execute(arguments: ToolArguments(["command": "echo ok"]))
        XCTAssertEqual(output, "FAKE: echo ok")
    }

    func testRealRunCommandToolExecutesSimpleCommandWithIntegerTimeout() async throws {
        let projectRoot = makeTempDir(prefix: "run_command_unit")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let tool = RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)

        let output = try await tool.execute(arguments: ToolArguments([
            "command": "printf 'unit-run-command-ok'",
            "timeout_seconds": 5
        ]))

        XCTAssertTrue(output.contains("Exit Code: 0"))
        XCTAssertTrue(output.contains("Timed Out: false"))
        XCTAssertTrue(output.contains("unit-run-command-ok"))
    }

    func testRealRunCommandToolDoesNotReportTimeoutForFastDirectoryListing() async throws {
        let projectRoot = makeTempDir(prefix: "run_command_listing")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let tool = RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)

        let output = try await tool.execute(arguments: ToolArguments([
            "command": "ls -la",
            "timeout_seconds": 1
        ]))

        XCTAssertTrue(output.contains("Exit Code: 0"))
        XCTAssertTrue(output.contains("Timed Out: false"))
    }
}
