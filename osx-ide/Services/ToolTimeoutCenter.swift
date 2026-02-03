import Foundation
import Combine

@MainActor
final class ToolTimeoutCenter: ObservableObject {
    static let shared = ToolTimeoutCenter()

    @Published private(set) var activeToolCallId: String?
    @Published private(set) var activeToolName: String?
    @Published private(set) var activeTargetFile: String?
    @Published private(set) var countdownSeconds: Int?
    @Published private(set) var isPaused: Bool = false

    private var lastProgressAtByToolCallId: [String: Date] = [:]
    private var timeoutSecondsByToolCallId: [String: TimeInterval] = [:]
    private var cancelledToolCallIds: Set<String> = []

    private var timerCancellable: AnyCancellable?

    private init() {
        timerCancellable = Timer
            .publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recomputeCountdown()
            }
    }

    func begin(toolCallId: String, toolName: String, targetFile: String?, timeoutSeconds: TimeInterval) {
        activeToolCallId = toolCallId
        activeToolName = toolName
        activeTargetFile = targetFile
        timeoutSecondsByToolCallId[toolCallId] = timeoutSeconds
        lastProgressAtByToolCallId[toolCallId] = Date()
        cancelledToolCallIds.remove(toolCallId)
        isPaused = false
        recomputeCountdown()
    }

    func markProgress(toolCallId: String) {
        lastProgressAtByToolCallId[toolCallId] = Date()
        recomputeCountdown()
    }

    func finish(toolCallId: String) {
        if activeToolCallId == toolCallId {
            activeToolCallId = nil
            activeToolName = nil
            activeTargetFile = nil
            countdownSeconds = nil
            isPaused = false
        }
        lastProgressAtByToolCallId[toolCallId] = nil
        timeoutSecondsByToolCallId[toolCallId] = nil
        cancelledToolCallIds.remove(toolCallId)
    }

    func togglePause() {
        isPaused.toggle()
        recomputeCountdown()
    }

    func cancel(toolCallId: String) {
        cancelledToolCallIds.insert(toolCallId)
        NotificationCenter.default.post(
            name: NSNotification.Name("CancelToolExecution"),
            object: nil,
            userInfo: ["toolCallId": toolCallId]
        )
    }

    func cancelActiveToolNow() {
        guard let toolCallId = activeToolCallId else { return }
        cancel(toolCallId: toolCallId)
    }

    func isCancelled(toolCallId: String) -> Bool {
        cancelledToolCallIds.contains(toolCallId)
    }

    func remainingSeconds(toolCallId: String) -> Int? {
        guard !isPaused else { return nil }
        guard let lastProgressAt = lastProgressAtByToolCallId[toolCallId] else { return nil }
        guard let timeoutSeconds = timeoutSecondsByToolCallId[toolCallId] else { return nil }
        let deadline = lastProgressAt.addingTimeInterval(timeoutSeconds)
        let remaining = Int(ceil(deadline.timeIntervalSinceNow))
        return remaining
    }

    private func recomputeCountdown() {
        guard let toolCallId = activeToolCallId else {
            countdownSeconds = nil
            return
        }
        guard let remaining = remainingSeconds(toolCallId: toolCallId) else {
            countdownSeconds = nil
            return
        }
        if remaining <= 5, remaining > 0 {
            countdownSeconds = remaining
        } else {
            countdownSeconds = nil
        }
    }
}
