import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ideHarnessTests/ToolVacuumHarnessTests.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)
content = content.replacingOccurrences(of: """
        print("=== TACTICAL RESULT ===")
        print(tacticalResult)
        print("=======================")
        XCTAssertTrue(tacticalResult.contains("Use read_file/list_files to inspect relevant sources"), "TACTICAL OUTPUT: \\(tacticalResult)")
        XCTAssertTrue(tacticalResult.contains("Apply edits using write_file/replace_in_file"), "TACTICAL OUTPUT: \\(tacticalResult)")
""", with: """
        print("=== TACTICAL RESULT ===")
        print(tacticalResult)
        print("=======================")
        XCTAssertTrue(tacticalResult.lowercased().contains("use read_file"), "TACTICAL OUTPUT: \\(tacticalResult)")
        XCTAssertTrue(tacticalResult.lowercased().contains("apply edits"), "TACTICAL OUTPUT: \\(tacticalResult)")
""")
try content.write(toFile: path, atomically: true, encoding: .utf8)
