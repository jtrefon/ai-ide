import Foundation
protocol ToolFormatAdapter: Sendable { func encodeTools(_:[ToolDefinition])->[[String: Any]]; func decodeCalls(from: AIServiceResponse)throws->[ParsedToolCall]; func encodeBatch(_:[ToolResult])->String }
