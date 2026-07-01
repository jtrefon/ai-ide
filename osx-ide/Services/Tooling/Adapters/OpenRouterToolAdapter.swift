import Foundation
struct OpenRouterToolAdapter: ToolFormatAdapter {
    func encodeTools(_ ts:[ToolDefinition])->[[String: Any]]{ts.map{t in["type":"function","function":["name":t.name,"description":t.description,"parameters":t.parameters.toDict()]]}}
    func decodeCalls(from r: AIServiceResponse)throws->[ParsedToolCall]{guard let cs = r.toolCalls else{return[]};return try cs.map{ParsedToolCall(id:$0.id,toolName:$0.name,args: ToolValue.from(dict:$0.arguments))}}
    func encodeBatch(_ rs:[ToolResult])->String{ToolFeedbackFormatter().formatBatch(rs.map{$0.feedback})}
}
