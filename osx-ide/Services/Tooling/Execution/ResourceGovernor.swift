import Foundation
actor ResourceGovernor { let pool: WorkerPool; init(m: Int = 4){pool = WorkerPool(m: m)}
    func exec(req: ToolExecutionRequest,exec: ToolExecutor)async->ToolFeedback{await pool.exec(req: req,exec: exec)}
}
