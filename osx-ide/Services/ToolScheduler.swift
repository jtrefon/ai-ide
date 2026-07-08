import Foundation

actor ToolScheduler {
    struct Configuration: Sendable {
        let maxConcurrentReadTasks: Int
        let maxConcurrentSessionTasks: Int

        init(maxConcurrentReadTasks: Int = 4, maxConcurrentSessionTasks: Int = 2) {
            self.maxConcurrentReadTasks = max(1, maxConcurrentReadTasks)
            self.maxConcurrentSessionTasks = max(1, maxConcurrentSessionTasks)
        }
    }

    private let configuration: Configuration
    private let readSemaphore: AsyncSemaphore
    private let sessionSemaphore: AsyncSemaphore
    private let writeLocks = AsyncLockMap<String>()
    private let sessionLocks = AsyncLockMap<String>()
    private var globalLockCount = 0
    private var globalLockWaiters: [CheckedContinuation<Void, Never>] = []

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.readSemaphore = AsyncSemaphore(value: configuration.maxConcurrentReadTasks)
        self.sessionSemaphore = AsyncSemaphore(value: configuration.maxConcurrentSessionTasks)
    }

    // MARK: - Legacy API (backward compat)

    func runReadTask<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        await readSemaphore.wait()
        defer { Task { await readSemaphore.signal() } }
        return try await operation()
    }

    func runWriteTask<T: Sendable>(
        pathKey: String,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await writeLocks.lock(for: pathKey)
        defer { Task { await writeLocks.unlock(for: pathKey) } }
        return try await operation()
    }

    // MARK: - ToolIsolation API

    func schedule<T: Sendable>(
        isolation: ToolIsolation,
        pathKey: String?,
        sessionId: String?,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        switch isolation {
        case .concurrent:
            return try await operation()
        case .pathIsolated:
            let key = pathKey ?? "_default"
            await writeLocks.lock(for: key)
            defer { Task { await writeLocks.unlock(for: key) } }
            return try await operation()
        case .sessionIsolated:
            let key = sessionId ?? "_default"
            await sessionLocks.lock(for: key)
            defer { Task { await sessionLocks.unlock(for: key) } }
            return try await operation()
        case .globallySerial:
            await acquireGlobalLock()
            defer { releaseGlobalLock() }
            return try await operation()
        }
    }

    private func acquireGlobalLock() async {
        await withCheckedContinuation { continuation in
            if globalLockCount == 0 {
                globalLockCount = 1
                continuation.resume()
            } else {
                globalLockWaiters.append(continuation)
            }
        }
    }

    private func releaseGlobalLock() {
        if !globalLockWaiters.isEmpty {
            let next = globalLockWaiters.removeFirst()
            next.resume()
        } else {
            globalLockCount = 0
        }
    }
}
