import Foundation
actor ToolLoopGuard { var hist:[String: Set<String>]=[:]
    func recordTurn(cid: String,calls:[ParsedToolCall]){hist[cid]=Set(calls.map{$0.signature})}
    func shouldAbort(cid: String,calls:[ParsedToolCall],maxR: Int = 3)->Bool{guard let h = hist[cid]else{return false};let cur = Set(calls.map{$0.signature});return h.intersection(cur).count>=maxR}
}
