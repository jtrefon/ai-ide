import Foundation

public struct CheckpointEntry: Codable, Sendable {
    public let relativePath: String
    public let existed: Bool
    public let stagedRelativeBackupPath: String?

    public init(relativePath: String, existed: Bool, stagedRelativeBackupPath: String?) {
        self.relativePath = relativePath
        self.existed = existed
        self.stagedRelativeBackupPath = stagedRelativeBackupPath
    }
}
