import Foundation

public struct IndexedResource {
    public let id: String
    public let url: URL
    public let language: CodeLanguage
    public let lastModified: Date
    public let contentHash: String
}
