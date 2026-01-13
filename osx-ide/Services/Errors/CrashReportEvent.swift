public struct CrashReportEvent: Codable, Sendable {
    public let ts: String
    public let session: String
    public let operation: String
    public let errorType: String
    public let errorDescription: String
    public let file: String
    public let function: String
    public let line: Int
    public let metadata: [String: String]?
}
