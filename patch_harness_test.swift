import Foundation

let path = "/Users/jack/Projects/osx/osx-ide/osx-ideHarnessTests/ToolLoopDropoutHarnessTests.swift"
var content = try String(contentsOfFile: path, encoding: .utf8)
content = content.replacingOccurrences(of: """
        let capturedRequests = scriptedService.capturedHistoryRequests()
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }
        print("====== DEBUG STAGES ======")
        for (i, req) in capturedRequests.enumerated() {
            print("[\\(i)] \\(req.stage?.rawValue ?? "nil") - \\(req.messages.last?.content ?? "")")
        }
        print("==========================").joined(separator: ",")
""", with: """
        let capturedRequests = scriptedService.capturedHistoryRequests()
        let requestStages = capturedRequests.map { $0.stage?.rawValue ?? "nil" }
        print("====== DEBUG STAGES ======")
        for (i, req) in capturedRequests.enumerated() {
            print("[\\(i)] \\(req.stage?.rawValue ?? "nil") - \\(req.messages.last?.content ?? "")")
        }
        print("==========================")
""")
try content.write(toFile: path, atomically: true, encoding: .utf8)
