import Foundation
actor FileAccessLedger { var reads:[String: Set<String>]=[:]
    func key(_ c: String,_ t: String)->String{c+":"+t}
    func startTurn(cid: String,tid: String){reads[key(cid,tid)]=[]}; func endTurn(_ tid: String){reads = reads.filter{!$0.key.hasSuffix(":"+tid)}}
    func recordRead(path: String,cid: String,tid: String){reads[key(cid,tid),default:[]].insert((path as NSString).standardizingPath)}
    func hasRead(path: String,cid: String,tid: String)->Bool{reads[key(cid,tid)]?.contains((path as NSString).standardizingPath) ?? false}
}
