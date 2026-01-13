import Foundation

actor ToolScheduler: Sendable {
    struct Configuration: Sendable {
        let maxConcurrentReadTasks: Int

        init(maxConcurrentReadTasks: Int = 4) {
            self.maxConcurrentReadTasks = max(1, maxConcurrentReadTasks)
        }
    }

    private let configuration: Configuration
    private let readSemaphore: AsyncSemaphore
    private let writeLocks = AsyncLockMap<String>()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.readSemaphore = AsyncSemaphore(value: configuration.maxConcurrentReadTasks)
    }

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
}
