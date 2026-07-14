import Foundation

/// Model-agnostic processor for tool results bound for a model context.
///
/// Centralizes the "Context Access Layer" policy that was previously duplicated
/// (and only wired into the cloud pipeline): enforce a model-aware character
/// cap, offload the full text to disk so truncation is *recoverable*, and for
/// log-like output, summarize instead of silently dropping bytes.
///
/// Both the cloud (`OpenAICompatibleChatService`) and local
/// (`LocalModelProcessAIService`) pipelines route through this so large tool
/// output is handled identically regardless of which model answers. The
/// deterministic `LogSummarizer` is the canonical summarizer; an
/// LLM/AI-based summarization stage can be slotted in here later without
/// touching either pipeline.
enum ToolResultProcessor {
    static func process(
        payload: String,
        toolCallId: String,
        modelID: String,
        projectRoot: URL?
    ) -> String {
        let limit = ToolOutputArchive.effectiveToolOutputLimit(modelID: modelID)
        guard payload.count > limit else { return payload }

        let path = ToolOutputArchive.offload(toolCallId: toolCallId, full: payload, projectRoot: projectRoot)
        let logSummary = LogSummarizer.summarize(payload)

        if logSummary.isLogOutput {
            let summaryBlock = logSummary.brief.isEmpty ? "(log output)" : logSummary.brief
            return """
            \(summaryBlock)

            [tool output truncated at \(limit) chars; full saved at \(path)]
            Next: read with start_line/end_line, or delegate to the research subagent.
            """
        }

        let preview = String(payload.prefix(limit))
        return """
        \(preview)

        [tool output truncated at \(limit) chars; full saved at \(path)]
        Next: read with start_line/end_line, or delegate to the research subagent.
        """
    }
}
