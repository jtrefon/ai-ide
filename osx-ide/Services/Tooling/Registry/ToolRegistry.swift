import Foundation

final class ToolRegistry: @unchecked Sendable, ToolRegistryProtocol {
    private var byName: [String: ToolDefinition] = [:]
    private var byMode: [AgentMode: [ToolDefinition]] = [:]
    private let lock = NSLock()

    func register(_ t: ToolDefinition) {
        lock.lock()
        precondition(byName[t.name] == nil)
        byName[t.name] = t
        for m in t.allowedModes { byMode[m, default: []].append(t) }
        lock.unlock()
    }

    func tool(named: String) -> ToolDefinition? {
        lock.lock()
        let result = byName[named]
        lock.unlock()
        return result
    }

    func tools(for mode: AgentMode) -> [ToolDefinition] {
        lock.lock()
        let result = byMode[mode] ?? []
        lock.unlock()
        return result
    }

    var allTools: [ToolDefinition] {
        lock.lock()
        let result = Array(byName.values)
        lock.unlock()
        return result
    }

    var count: Int {
        lock.lock()
        let result = byName.count
        lock.unlock()
        return result
    }
}
