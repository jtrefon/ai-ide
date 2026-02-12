import Foundation

struct LocalModelArtifact: Hashable, Sendable {
    let fileName: String
    let url: URL
}

struct LocalModelDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let artifacts: [LocalModelArtifact]
}
