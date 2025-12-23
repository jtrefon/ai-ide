import XCTest
@testable import osx_ide

final class CodebaseIndexTests: XCTestCase {
    func testDatabaseManagerCreatesSchema() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("codebase_index_test_\(UUID().uuidString).sqlite").path
        _ = try DatabaseManager(path: dbPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath))
    }

    func testDatabaseManagerSavesAndLoadsMemory() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("codebase_index_memory_test_\(UUID().uuidString).sqlite").path
        let db = try DatabaseManager(path: dbPath)

        let entry = MemoryEntry(tier: .midTerm, content: "Test memory", category: "decision", protectionLevel: 42)
        try db.saveMemory(entry)

        let loaded = try db.getMemories(tier: .midTerm)
        XCTAssertEqual(loaded.first?.content, "Test memory")
        XCTAssertEqual(loaded.first?.protectionLevel, 42)
    }

    func testSwiftParserExtractsClass() {
        let code = """
        final class MyService {
            func doThing() {}
        }
        """

        let symbols = SwiftParser.parse(content: code, resourceId: "test")
        XCTAssertTrue(symbols.contains(where: { $0.kind == .class && $0.name == "MyService" }))
        XCTAssertTrue(symbols.contains(where: { $0.kind == .function && $0.name == "doThing" }))
    }
}
