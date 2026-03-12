import Foundation

let path = "/tmp/harness_output2.txt"
if let content = try? String(contentsOfFile: path, encoding: .utf8) {
    let lines = content.components(separatedBy: .newlines)
    let errorLines = lines.filter { $0.contains("TACTICAL OUTPUT:") || $0.contains("XCTAssert") }
    print(errorLines.joined(separator: "\n"))
}
