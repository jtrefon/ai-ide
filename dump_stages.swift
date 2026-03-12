import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ideHarnessTests/ToolLoopDropoutHarnessTests.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)
content = content.replacingOccurrences(of: """
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }
        try? requestStages.joined(separator: ",").write(to: URL(fileURLWithPath: "/tmp/test_output.txt"), atomically: true, encoding: .utf8)
""", with: """
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }
        var logContent = "STAGES: \\(requestStages)\\n"
        for (i, req) in capturedRequests.enumerated() {
            logContent += "REQ \\(i): \\(req.stage?.rawValue ?? "nil") -> \\(req.messages.last?.content ?? "")\\n"
        }
        try? logContent.write(to: URL(fileURLWithPath: "/tmp/harness_debug.log"), atomically: true, encoding: .utf8)
""")
try content.write(toFile: path, atomically: true, encoding: .utf8)
