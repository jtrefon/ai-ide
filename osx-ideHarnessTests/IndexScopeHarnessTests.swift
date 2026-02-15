import XCTest
@testable import osx_ide

@MainActor
final class IndexScopeHarnessTests: XCTestCase {
    private struct NoopAIService: AIService, @unchecked Sendable {
        func sendMessage(_ request: AIServiceMessageWithProjectRootRequest) async throws -> AIServiceResponse {
            _ = request
            return AIServiceResponse(content: nil, toolCalls: nil)
        }

        func sendMessage(_ request: AIServiceHistoryRequest) async throws -> AIServiceResponse {
            _ = request
            return AIServiceResponse(content: nil, toolCalls: nil)
        }

        func explainCode(_ code: String) async throws -> String { _ = code; return "" }
        func refactorCode(_ code: String, instructions: String) async throws -> String { _ = code; _ = instructions; return "" }
        func generateCode(_ prompt: String) async throws -> String { _ = prompt; return "" }
        func fixCode(_ code: String, error: String) async throws -> String { _ = code; _ = error; return "" }
    }

    func testIndexIgnoresOutOfProjectFileEvents() async throws {
        let projectRoot = makeTempDir(prefix: "index_scope_project")
        let externalRoot = makeTempDir(prefix: "index_scope_external")
        let indexStorage = makeTempDir(prefix: "index_scope_storage")
        defer {
            cleanup(projectRoot)
            cleanup(externalRoot)
            cleanup(indexStorage)
        }

        let inProjectFile = projectRoot.appendingPathComponent("src/App.tsx")
        let externalFile = externalRoot.appendingPathComponent("outside/Leak.ts")
        try writeFile(inProjectFile, content: "export default function App() { return null }\n")
        try writeFile(externalFile, content: "export const leak = true\n")

        let eventBus = EventBus()
        let config = IndexConfiguration(
            enabled: true,
            debounceMs: 10,
            excludePatterns: IndexConfiguration.default.excludePatterns,
            storageDirectoryPath: indexStorage.path
        )
        let index = try CodebaseIndex(
            eventBus: eventBus,
            projectRoot: projectRoot,
            aiService: NoopAIService(),
            config: config
        )
        index.start()

        eventBus.publish(FileModifiedEvent(url: inProjectFile))
        eventBus.publish(FileModifiedEvent(url: externalFile))

        try await Task.sleep(nanoseconds: 400_000_000)

        let listed = try await index.listIndexedFiles(matching: nil, limit: 200, offset: 0)
        XCTAssertTrue(listed.contains(where: { $0 == "src/App.tsx" }), "In-project file should be indexed")
        XCTAssertFalse(listed.contains(where: { $0.contains("Leak.ts") || $0.contains(externalRoot.path) }), "Out-of-project file must never be indexed or listed")
    }

    func testHarnessCanStoreIndexDatabaseOutsideProjectWorkspace() async throws {
        let projectRoot = makeTempDir(prefix: "index_scope_project")
        let isolatedStorage = makeTempDir(prefix: "index_scope_storage")
        defer {
            cleanup(projectRoot)
            cleanup(isolatedStorage)
        }

        let config = IndexConfiguration(
            enabled: true,
            debounceMs: 10,
            excludePatterns: IndexConfiguration.default.excludePatterns,
            storageDirectoryPath: isolatedStorage.path
        )

        let index = try CodebaseIndex(
            eventBus: EventBus(),
            projectRoot: projectRoot,
            aiService: NoopAIService(),
            config: config
        )
        index.start()

        let stats = try await index.getStats()
        XCTAssertTrue(stats.databasePath.hasPrefix(isolatedStorage.path), "Index database should be created in isolated harness storage")
        XCTAssertFalse(stats.isDatabaseInWorkspace, "Database should not be stored under project workspace when override is set")
    }

    private func writeFile(_ url: URL, content: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeTempDir(prefix: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
