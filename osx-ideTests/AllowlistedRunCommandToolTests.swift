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

    func testAllowlistedWrapperAllowsSessionFollowUpWithoutRevalidatingCommand() async throws {
        let tool = AllowlistedRunCommandTool(base: FakeRunCommandTool(), allowedPrefixes: ["echo "])

        let output = try await tool.execute(arguments: ToolArguments([
            "action": "wait",
            "session_id": "existing-session"
        ]))

        XCTAssertEqual(output, "FAKE: ")
    }

    func testRealRunCommandToolExecutesSimpleCommandAndReturnsExitedStatus() async throws {
        let projectRoot = makeTempDir(prefix: "run_command_unit")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let tool = RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)

        let output = try await tool.execute(arguments: ToolArguments([
            "command": "printf 'unit-run-command-ok'",
            "wait_seconds": 5
        ]))

        XCTAssertTrue(output.contains("\"status\" : \"exited\""))
        XCTAssertTrue(output.contains("\"exit_code\" : 0"))
        XCTAssertTrue(output.contains("unit-run-command-ok"))
    }

    func testRealRunCommandToolReturnsRunningSessionAndCanWaitForCompletion() async throws {
        let projectRoot = makeTempDir(prefix: "run_command_wait")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let tool = RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)

        let first = try await tool.execute(arguments: ToolArguments([
            "action": "start",
            "command": "sleep 2; printf 'done'",
            "wait_seconds": 1
        ]))

        XCTAssertTrue(first.contains("\"status\" : \"running\""))
        guard let sessionId = sessionId(from: first) else {
            XCTFail("Expected session_id in running response")
            return
        }

        let second = try await tool.execute(arguments: ToolArguments([
            "action": "wait",
            "session_id": sessionId,
            "wait_seconds": 3
        ]))

        XCTAssertTrue(second.contains("\"status\" : \"exited\""))
        XCTAssertTrue(second.contains("\"exit_code\" : 0"))
        XCTAssertTrue(second.contains("done"))
    }

    func testRealRunCommandToolSupportsInteractiveInput() async throws {
        let projectRoot = makeTempDir(prefix: "run_command_input")
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let pathValidator = PathValidator(projectRoot: projectRoot)
        let tool = RunCommandTool(projectRoot: projectRoot, pathValidator: pathValidator)

        let first = try await tool.execute(arguments: ToolArguments([
            "action": "start",
            "command": "read name; printf 'hello:%s' \"$name\"",
            "wait_seconds": 1
        ]))

        XCTAssertTrue(first.contains("\"status\" : \"running\""))
        guard let sessionId = sessionId(from: first) else {
            XCTFail("Expected session_id in interactive response")
            return
        }

        let second = try await tool.execute(arguments: ToolArguments([
            "action": "send_input",
            "session_id": sessionId,
            "input": "jack",
            "append_newline": true,
            "wait_seconds": 2
        ]))

        XCTAssertTrue(second.contains("\"status\" : \"exited\""))
        XCTAssertTrue(second.contains("hello:jack"))
    }

    private func sessionId(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["session_id"] as? String
    }
}
