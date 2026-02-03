import Foundation

actor AsyncLockMap <Key: Hashable & Sendable>{
    private actor Lock {
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

    private var locks: [Key: Lock] = [:]

    func lock(for key: Key) async {
        let lock = getOrCreateLock(for: key)
        await lock.lock()
    }

    func unlock(for key: Key) async {
        if let lock = locks[key] {
            await lock.unlock()
        }
    }

    private func getOrCreateLock(for key: Key) -> Lock {
        if let existing = locks[key] {
            return existing
        }
        let newLock = Lock()
        locks[key] = newLock
        return newLock
    }
}
