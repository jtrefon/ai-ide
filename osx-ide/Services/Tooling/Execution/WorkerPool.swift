import Foundation
actor WorkerPool { let maxC: Int; var active = 0; var queue:[CheckedContinuation<Void,Never>]=[]; init(m: Int = 4){maxC = max(1,m)}
    func exec(req: ToolExecutionRequest,exec: ToolExecutor)async->ToolFeedback{await wait();defer{rel()};return await exec.execute(request: req)}
    func wait()async{if active<maxC{active+=1}else{await withCheckedContinuation{queue.append($0)}}}; func rel(){if queue.isEmpty{active-=1}else{queue.removeFirst().resume()}}
}
