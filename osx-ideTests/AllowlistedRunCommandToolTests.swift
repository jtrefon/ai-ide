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

        func execute(arguments: ToolArguments, onProgress: @Sendable @escaping (String) -> Void) async throws -> String {
            let arguments = arguments.raw
            let cmd = (arguments["command"] as? String) ?? ""
            onProgress("FAKE_PROGRESS")
            return "FAKE: \(cmd)"
        }
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
}
