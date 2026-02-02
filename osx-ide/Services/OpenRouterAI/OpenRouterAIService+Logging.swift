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
                "model": context.model,
                "messageCount": context.messageCount,
                "toolCount": context.toolCount,
                "mode": context.mode?.rawValue as Any,
                "projectRoot": context.projectRoot?.path as Any
            ])
        )

        await AIToolTraceLogger.shared.log(type: "openrouter.request", data: [
            "model": context.model,
            "messages": context.messageCount,
            "tools": context.toolCount,
            "mode": context.mode?.rawValue as Any,
            "projectRoot": context.projectRoot?.path as Any
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
