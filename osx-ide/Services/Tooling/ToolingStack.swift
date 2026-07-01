import Foundation

struct ToolingStack: Sendable {
    let registry: ToolRegistryProtocol
    let orchestrator: CoderOrchestrator
    let scheduler: SequentialScheduler
    let governor: ResourceGovernor
    let executor: ToolExecutor
    let adapter: ToolFormatAdapter
}
