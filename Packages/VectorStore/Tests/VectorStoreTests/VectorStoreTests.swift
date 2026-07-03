import Foundation
import Testing
@testable import VectorStore

struct VectorStoreTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vectorstore_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func makeService() -> VectorStoreService {
        let config = VectorStoreConfiguration(
            storePath: tempDir,
            dimensions: 4,
            factoryString: "IDMap,Flat"
        )
        return VectorStoreService.create(with: config)
    }

    @Test
    func testAddAndSearch() async throws {
        let service = makeService()
        try await service.load()

        try await service.addEntry(
            text: "test entry",
            vector: [1.0, 0.0, 0.0, 0.0],
            source: "test"
        )

        let results = try await service.search(queryVector: [1.0, 0.0, 0.0, 0.0], limit: 5)
        #expect(results.count == 1)
        #expect(results[0].score > 0.9)
    }

    @Test
    func testPersistence() async throws {
        let config = VectorStoreConfiguration(
            storePath: tempDir,
            dimensions: 4,
            factoryString: "IDMap,Flat"
        )

        do {
            let service = VectorStoreService.create(with: config)
            try await service.load()
            try await service.addEntry(
                text: "persist me",
                vector: [0.0, 1.0, 0.0, 0.0],
                source: "test"
            )
            try await service.save()
        }

        do {
            let service = VectorStoreService.create(with: config)
            try await service.load()
            let results = try await service.search(queryVector: [0.0, 1.0, 0.0, 0.0], limit: 5)
            #expect(results.count == 1)
            #expect(results[0].metadata?.text == "persist me")
        }
    }

    @Test
    func testBatchAdd() async throws {
        let service = makeService()
        try await service.load()

        let catA: String? = nil
        let catB: String? = nil
        let catC: String? = nil
        let ids = try await service.addBatch(entries: [
            (text: "a", vector: [1, 0, 0, 0], source: "test", category: catA),
            (text: "b", vector: [0, 1, 0, 0], source: "test", category: catB),
            (text: "c", vector: [0, 0, 1, 0], source: "test", category: catC),
        ])
        #expect(ids.count == 3)

        let results = try await service.search(queryVector: [1, 0, 0, 0], limit: 5)
        #expect(results.count == 3)
        #expect(results[0].metadata?.text == "a")
    }

    @Test
    func testRemove() async throws {
        let service = makeService()
        try await service.load()

        let id = try await service.addEntry(
            text: "delete me",
            vector: [1, 0, 0, 0],
            source: "test"
        )
        #expect(await service.indexCount == 1)

        try await service.removeEntry(id: id)
        #expect(await service.indexCount == 0)
    }

    @Test
    func testRemoveAll() async throws {
        let service = makeService()
        try await service.load()

        let catX: String? = nil
        let catY: String? = nil
        try await service.addBatch(entries: [
            (text: "x", vector: [1, 0, 0, 0], source: "test", category: catX),
            (text: "y", vector: [0, 1, 0, 0], source: "test", category: catY),
        ])
        try await service.removeAll()
        #expect(await service.indexCount == 0)
        #expect(await service.entryCount == 0)
    }

    @Test
    func testCosineSimilarity() async throws {
        let service = makeService()
        try await service.load()

        try await service.addEntry(
            text: "similar",
            vector: [0.8, 0.6, 0.0, 0.0],
            source: "test"
        )
        try await service.addEntry(
            text: "different",
            vector: [0.0, 0.0, 0.8, 0.6],
            source: "test"
        )

        let results = try await service.search(queryVector: [1.0, 0.0, 0.0, 0.0], limit: 5)
        #expect(results.count == 2)
        #expect(results[0].metadata?.text == "similar")
        #expect(results[0].score > results[1].score)
    }
}

struct FAISSVectorIndexTests {
    @Test
    func testFAISSIndexLifecycle() throws {
        let idx = FAISSVectorIndex(dimensions: 4)
        try idx.add(id: 1, vector: [1, 0, 0, 0])
        try idx.add(id: 2, vector: [0, 1, 0, 0])
        #expect(idx.count == 2)

        let results = try idx.search(query: [1, 0, 0, 0], limit: 5)
        #expect(results.count == 2)
        #expect(results[0].id == 1)
    }

    @Test
    func testFAISSRemove() throws {
        let idx = FAISSVectorIndex(dimensions: 4)
        try idx.add(id: 1, vector: [1, 0, 0, 0])
        try idx.add(id: 2, vector: [0, 1, 0, 0])

        try idx.remove(ids: [1])
        #expect(idx.count == 1)

        let results = try idx.search(query: [1, 0, 0, 0], limit: 5)
        #expect(results.count == 1)
        #expect(results[0].id == 2)
    }

    @Test
    func testFAISSReset() throws {
        let idx = FAISSVectorIndex(dimensions: 4)
        try idx.add(id: 1, vector: [1, 0, 0, 0])
        try idx.reset()
        #expect(idx.count == 0)
    }

    @Test
    func testFAISSBatch() throws {
        let idx = FAISSVectorIndex(dimensions: 4)
        try idx.addBatch(ids: [1, 2, 3], vectors: [
            [1, 0, 0, 0],
            [0, 1, 0, 0],
            [0, 0, 1, 0],
        ])
        #expect(idx.count == 3)
    }
}
