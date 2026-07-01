import Foundation

struct SandboxDecorator: ToolExecutor {
    let inner: ToolExecutor
    let ledger: FileAccessLedger

    nonisolated func execute(request: ToolExecutionRequest) async -> ToolFeedback {
        if request.context.sandbox.enforceReadBeforeWrite,
           ["write_file", "delete_file"].contains(request.toolName),
           let p = request.arguments["path"]?.stringValue {
            if FileManager.default.fileExists(atPath: p),
               await !ledger.hasRead(path: p, cid: request.context.conversationId, tid: request.context.turnId) {
                return .mustReadFirst(p)
            }
        }
        let fb = await inner.execute(request: request)
        if request.toolName == "read_file",
           let p = request.arguments["path"]?.stringValue,
           fb.status == .success {
            await ledger.recordRead(path: p, cid: request.context.conversationId, tid: request.context.turnId)
        }
        return fb
    }
}
