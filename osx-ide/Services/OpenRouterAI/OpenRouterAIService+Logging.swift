import Foundation

extension OpenRouterAIService {
    internal func logRequestStart(
        _ context: RequestStartContext
    ) async {
        await AppLogger.shared.info(
            category: .ai,
            message: "openrouter.request_start",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": context.requestId,
                "providerName": context.providerName,
                "baseURL": context.baseURL,
                "streaming": context.streaming,
                "runId": context.runId as Any,
                "stage": context.stage?.rawValue as Any,
                "model": context.model,
                "messageCount": context.messageCount,
                "toolCount": context.toolCount,
                "mode": context.mode?.rawValue as Any,
                "projectRoot": context.projectRoot?.path as Any
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.request", data: [
            "providerName": context.providerName,
            "baseURL": context.baseURL,
            "streaming": context.streaming,
            "model": context.model,
            "messages": context.messageCount,
            "tools": context.toolCount,
            "mode": context.mode?.rawValue as Any,
            "projectRoot": context.projectRoot?.path as Any,
            "runId": context.runId as Any,
            "stage": context.stage?.rawValue as Any
        ])
    }

    internal func logRequestBody(requestId: String, bytes: Int) async {
        await AppLogger.shared.debug(
            category: .ai,
            message: "openrouter.request_body",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "bytes": bytes
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.request_body", data: [
            "bytes": bytes
        ])
    }

    internal func logRequestBodyContent(requestId: String, body: Data) async {
        guard let raw = String(data: body, encoding: .utf8) else { return }
        let preview = raw.prefix(2000)
        await AIToolTraceLogger.shared.log(type: "openrouter.request_body_content", data: [
            "requestId": requestId,
            "bodyBytes": body.count,
            "preview": String(preview)
        ])
    }

    internal func logStreamChunk(requestId: String, chunkJson: String, index: Int, parseSuccess: Bool, finishReason: String?) async {
        let preview = String(chunkJson.prefix(500))
        await AIToolTraceLogger.shared.log(type: "openrouter.stream_chunk", data: [
            "requestId": requestId,
            "chunkIndex": index,
            "parseSuccess": parseSuccess,
            "finishReason": finishReason as Any,
            "preview": preview
        ])
    }

    internal func logRequestError(requestId: String, status: Int, bodySnippet: String) async {
        await AppLogger.shared.error(
            category: .ai,
            message: "openrouter.request_error",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "status": status,
                "bodySnippet": bodySnippet
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.error", data: [
            "status": status,
            "bodySnippet": bodySnippet
        ])
    }

    internal func logRequestSuccess(
        requestId: String,
        contentLength: Int,
        toolCalls: Int,
        responseBytes: Int
    ) async {
        await AppLogger.shared.info(
            category: .ai,
            message: "openrouter.request_success",
            context: AppLogger.LogCallContext(metadata: [
                "requestId": requestId,
                "contentLength": contentLength,
                "toolCalls": toolCalls,
                "responseBytes": responseBytes
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.response", data: [
            "contentLength": contentLength,
            "toolCalls": toolCalls
        ])
    }
}
