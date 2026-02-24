import Foundation

public struct WorkspaceDirectoryDidChangeEvent: Event {
    public let url: URL?

    public init(url: URL?) {
        self.url = url
    }
}
