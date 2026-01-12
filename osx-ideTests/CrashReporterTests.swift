import Testing
import Foundation
@testable import osx_ide

@MainActor
struct CrashReporterTests {

    @Test func testCrashReporterWritesProjectCrashLog() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx-ide-crash-reporter-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        await CrashReporter.shared.setProjectRoot(tempRoot)

        let error = NSError(domain: "test.crash", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        await CrashReporter.shared.capture(
            error,
            context: CrashReportContext(operation: "CrashReporterTests.testCrashReporterWritesProjectCrashLog"),
            metadata: ["key": "value"],
            file: "CrashReporterTests.swift",
            function: #function,
            line: #line
        )

        let crashLogURL = tempRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("crash.ndjson")

        let data = try Data(contentsOf: crashLogURL)
        let content = String(decoding: data, as: UTF8.self)

        #expect(content.contains("crash.ndjson") == false, "Expected log to contain JSON events, not paths")
        #expect(content.contains("CrashReporterTests.testCrashReporterWritesProjectCrashLog"), "Expected operation to be present")
        #expect(content.contains("boom"), "Expected error description to be present")
        #expect(content.contains("\"key\""), "Expected metadata keys to be present")
    }
}
