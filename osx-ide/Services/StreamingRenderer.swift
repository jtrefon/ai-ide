//
//  StreamingRenderer.swift
//  osx-ide
//
//  Extracted from ConversationManager to handle streaming text rendering.
//

import Foundation

@MainActor
final class StreamingRenderer {
    /// Constants
    private let renderIntervalNanoseconds: UInt64 = 16_000_000
    private let maxCharactersPerTick = 8

    /// State
    private(set) var activeRunId: String?
    private(set) var draftAssistantMessageId: UUID?
    private(set) var draftAssistantText: String = ""
    private(set) var draftReasoningText: String = ""

    private var pendingStreamingBuffer: String = ""
    private var pendingReasoningBuffer: String = ""
    private var renderTask: Task<Void, Never>?

    /// Callbacks
    var onDraftUpdated: ((_ draftId: UUID, _ displayText: String, _ reasoning: String?) -> Void)?
    var draftMessageExists: ((_ draftId: UUID) -> Bool)?

    // MARK: - Lifecycle

    func beginStream(runId: String, draftId: UUID) {
        reset()
        activeRunId = runId
        draftAssistantMessageId = draftId
        draftAssistantText = ""
        draftReasoningText = ""
    }

    func feedContentChunk(_ chunk: String) {
        guard activeRunId != nil, draftAssistantMessageId != nil, !chunk.isEmpty else { return }
        pendingStreamingBuffer.append(chunk)
        startRenderLoopIfNeeded()
    }

    func feedReasoningChunk(_ chunk: String) {
        guard activeRunId != nil, draftAssistantMessageId != nil, !chunk.isEmpty else { return }
        pendingReasoningBuffer.append(chunk)
        startRenderLoopIfNeeded()
    }

    func flushPending() {
        guard let draftId = draftAssistantMessageId, !pendingStreamingBuffer.isEmpty else { return }
        guard draftMessageExists?(draftId) == true else {
            pendingStreamingBuffer = ""
            pendingReasoningBuffer = ""
            return
        }
        draftAssistantText.append(pendingStreamingBuffer)
        draftReasoningText.append(pendingReasoningBuffer)
        pendingStreamingBuffer = ""
        pendingReasoningBuffer = ""
        onDraftUpdated?(draftId, draftAssistantText, draftReasoningText.isEmpty ? nil : draftReasoningText)
    }

    func reset() {
        activeRunId = nil
        draftAssistantMessageId = nil
        draftAssistantText = ""
        draftReasoningText = ""
        pendingStreamingBuffer = ""
        pendingReasoningBuffer = ""
        renderTask?.cancel()
        renderTask = nil
    }

    func cancel() {
        renderTask?.cancel()
        renderTask = nil
    }

    // MARK: - Render Loop

    private func startRenderLoopIfNeeded() {
        guard renderTask == nil else { return }
        guard let draftId = draftAssistantMessageId else { return }
        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.renderTask = nil }
            while self.activeRunId != nil {
                guard !Task.isCancelled else { break }

                if self.pendingStreamingBuffer.isEmpty {
                    do { try await Task.sleep(nanoseconds: self.renderIntervalNanoseconds) } catch { break }
                    continue
                }

                let delta = self.dequeue(from: &self.pendingStreamingBuffer)
                let reasoningDelta = self.dequeue(from: &self.pendingReasoningBuffer)
                guard !delta.isEmpty || !reasoningDelta.isEmpty else {
                    do { try await Task.sleep(nanoseconds: self.renderIntervalNanoseconds) } catch { break }
                    continue
                }
                guard self.draftMessageExists?(draftId) == true else { break }

                self.draftAssistantText.append(delta)
                self.draftReasoningText.append(reasoningDelta)
                self.onDraftUpdated?(draftId, self.draftAssistantText, self.draftReasoningText.isEmpty ? nil : self.draftReasoningText)

                do { try await Task.sleep(nanoseconds: self.renderIntervalNanoseconds) } catch { break }
            }
        }
    }

    private func dequeue(from buffer: inout String) -> String {
        guard !buffer.isEmpty else { return "" }
        let take = min(maxCharactersPerTick, buffer.count)
        let splitIndex = buffer.index(buffer.startIndex, offsetBy: take)
        let chunk = String(buffer[..<splitIndex])
        buffer.removeSubrange(buffer.startIndex..<splitIndex)
        return chunk
    }
}
