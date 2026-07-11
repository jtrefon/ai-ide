import XCTest
@testable import osx_ide
import Combine

@MainActor
final class NetworkRetryHarnessTests: XCTestCase {

    private final class RecordingEventBus: EventBusProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var networkOfflineEvents: [ProviderIssueStatusEvent] = []
        private(set) var resolvedEvents: [ProviderIssueStatusEvent] = []

        func publish<E: Event>(_ event: E) {
            if let issue = event as? ProviderIssueStatusEvent {
                lock.withLock {
                    if issue.statusKind == .networkOffline {
                        networkOfflineEvents.append(issue)
                    } else if issue.statusKind == .resolved {
                        resolvedEvents.append(issue)
                    }
                }
            }
        }

        func subscribe<E: Event>(to eventType: E.Type, handler: @escaping (E) -> Void) -> AnyCancellable {
            AnyCancellable {}
        }
    }

    private final class FlakyAIService: AIService, @unchecked Sendable {
        private let lock = NSLock()
        private var remainingFailures: Int
        private let error: AppError

        init(failures: Int, error: AppError) {
            self.remainingFailures = failures
            self.error = error
        }

        private func maybeThrow() throws -> AIServiceResponse {
            let shouldThrow = lock.withLock { () -> Bool in
                if remainingFailures > 0 {
                    remainingFailures -= 1
                    return true
                }
                return false
            }
            if shouldThrow { throw error }
            return AIServiceResponse(content: "recovered", toolCalls: nil)
        }

        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            try maybeThrow()
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            try maybeThrow()
        }

        func sendMessageStreaming(_ request: AIServiceHistoryRequest, runId: String) async throws -> AIServiceResponse {
            try maybeThrow()
        }
    }

    private func coordinator(with service: AIService, eventBus: RecordingEventBus) -> AIInteractionCoordinator {
        AIInteractionCoordinator(aiService: service, codebaseIndex: nil, eventBus: eventBus)
    }

    private func request() -> AIInteractionCoordinator.SendMessageWithRetryRequest {
        AIInteractionCoordinator.SendMessageWithRetryRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            tools: [],
            mode: .agent,
            projectRoot: URL(fileURLWithPath: "/tmp"),
            runId: UUID().uuidString,
            stage: .tool_loop,
            conversationId: UUID().uuidString
        )
    }

    private let networkError = AppError.aiServiceError(
        "AIService.sendMessageStreaming failed: The Internet connection appears to be offline."
    )

    func testNetworkErrorRetriesWithBannerThenSucceeds() async throws {
        let eventBus = RecordingEventBus()
        let service = FlakyAIService(failures: 2, error: networkError)
        let coordinator = coordinator(with: service, eventBus: eventBus)

        let result = await coordinator.sendMessageWithRetry(request())

        let response = try result.get()
        XCTAssertEqual(response.content, "recovered")
        XCTAssertGreaterThanOrEqual(eventBus.networkOfflineEvents.count, 1)
        XCTAssertNotNil(eventBus.networkOfflineEvents.first?.cooldownUntil,
                        "Network banner should carry a countdown (cooldownUntil)")
        XCTAssertGreaterThanOrEqual(eventBus.resolvedEvents.count, 1,
                                    "Banner should clear (resolved) once the connection recovers")
    }

    func testNetworkErrorExhaustsBudgetThenSurrenders() async throws {
        let eventBus = RecordingEventBus()
        let service = FlakyAIService(failures: 10, error: networkError)
        let coordinator = coordinator(with: service, eventBus: eventBus)

        let result = await coordinator.sendMessageWithRetry(request())

        switch result {
        case .success:
            XCTFail("After exhausting the escalation budget the run should surrender")
        case .failure:
            break
        }
        XCTAssertGreaterThanOrEqual(eventBus.networkOfflineEvents.count, 1)
    }

    func testNonNetworkErrorDoesNotTriggerNetworkBanner() async throws {
        let eventBus = RecordingEventBus()
        let service = FlakyAIService(failures: 10,
                                     error: AppError.aiServiceError("Something unrelated broke"))
        let coordinator = coordinator(with: service, eventBus: eventBus)

        let result = await coordinator.sendMessageWithRetry(request())

        switch result {
        case .success:
            XCTFail("Generic error should not be retried indefinitely")
        case .failure:
            break
        }
        XCTAssertEqual(eventBus.networkOfflineEvents.count, 0,
                       "Generic errors must not be misclassified as network connectivity")
    }
}
