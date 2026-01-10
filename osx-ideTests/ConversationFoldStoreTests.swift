import XCTest
@testable import osx_ide

@MainActor
final class ConversationFoldStoreTests: XCTestCase {
    func testFoldStoreWriteListRead() async throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_fold_store_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let store = ConversationFoldStore(projectRoot: projectRoot)
        let entry = try await store.write(summary: "summary", content: "content")

        let indexURL = projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("folds", isDirectory: true)
            .appendingPathComponent("index.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexURL.path))

        let contentURL = projectRoot
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("chat", isDirectory: true)
            .appendingPathComponent("folds", isDirectory: true)
            .appendingPathComponent("\(entry.id).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentURL.path))

        let entries = try await store.list(limit: 10)
        XCTAssertTrue(entries.contains(where: { $0.id == entry.id }))

        let readBack = try await store.read(id: entry.id)
        XCTAssertEqual(readBack, "content")
    }
}
