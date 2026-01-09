import Foundation

actor ToolScheduler: Sendable {
    actor _AsyncLock {
        private var isLocked: Bool = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func lock() async {
            if !isLocked {
                isLocked = true
                return
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            isLocked = true
        }

        func unlock() {
            if !waiters.isEmpty {
                let next = waiters.removeFirst()
                next.resume()
            } else {
                isLocked = false
            }
        }
    }

    actor _AsyncLockMap<Key: Hashable & Sendable>: Sendable {
        private var locks: [Key: _AsyncLock] = [:]

        func lock(for key: Key) async {
            let lock = getOrCreateLock(for: key)
            await lock.lock()
        }

        func unlock(for key: Key) async {
            if let lock = locks[key] {
                await lock.unlock()
            }
        }

        private func getOrCreateLock(for key: Key) -> _AsyncLock {
            if let existing = locks[key] {
                return existing
            }
            let newLock = _AsyncLock()
            locks[key] = newLock
            return newLock
        }
    }

    struct Configuration: Sendable {
        let maxConcurrentReadTasks: Int

        init(maxConcurrentReadTasks: Int = 4) {
            self.maxConcurrentReadTasks = max(1, maxConcurrentReadTasks)
        }
    }

    private let configuration: Configuration
    private let readSemaphore: AsyncSemaphore
    private let writeLocks = _AsyncLockMap<String>()

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.readSemaphore = AsyncSemaphore(value: configuration.maxConcurrentReadTasks)
    }

    func runReadTask<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        await readSemaphore.wait()
        defer { Task { await readSemaphore.signal() } }
        return try await operation()
    }

    func runWriteTask<T: Sendable>(pathKey: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        await writeLocks.lock(for: pathKey)
        defer { Task { await writeLocks.unlock(for: pathKey) } }
        return try await operation()
    }
}

actor AsyncSemaphore: Sendable {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(0, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            value += 1
        }
    }
}
