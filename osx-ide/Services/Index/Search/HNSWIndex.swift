import Foundation

final class HNSWIndex: @unchecked Sendable {
    private let lock = NSLock()

    final class Node {
        let id: String
        let normalizedVector: [Float]
        let level: Int
        var connections: [Set<String>]
        var isDeleted: Bool

        init(id: String, vector: [Float], level: Int) {
            self.id = id
            let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            self.normalizedVector = norm > 0 ? vector.map { $0 / norm } : vector
            self.level = level
            self.connections = Array(repeating: [], count: level + 1).map { _ in Set<String>() }
            self.isDeleted = false
        }
    }

    private var nodes: [String: Node] = [:]
    private var entryPointId: String?
    private var currentMaxLevel: Int = 0
    private var deletedCount: Int = 0

    private let M: Int
    private let Mmax: Int
    private let Mmax0: Int
    private let efConstruction: Int
    private let mL: Float

    init(M: Int = 16, efConstruction: Int = 200) {
        self.M = M
        self.Mmax = M
        self.Mmax0 = 2 * M
        self.efConstruction = efConstruction
        self.mL = 1.0 / log(Float(M))
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return nodes.isEmpty
    }

    var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return nodes.count - deletedCount
    }

    func insert(id: String, vector: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        insertLocked(id: id, vector: vector)
    }

    private func insertLocked(id: String, vector: [Float]) {
        guard !vector.isEmpty else { return }

        if let existing = nodes[id], !existing.isDeleted {
            existing.isDeleted = true
            deletedCount += 1
        }

        let level = generateLevel()
        let node = Node(id: id, vector: vector, level: level)
        nodes[id] = node

        guard let entryId = entryPointId, let _ = nodes[entryId] else {
            entryPointId = id
            currentMaxLevel = level
            return
        }

        var entryPoint = entryId
        let currMaxLevel = currentMaxLevel

        if level < currMaxLevel {
            for layer in stride(from: currMaxLevel, to: level, by: -1) {
                let nearest = searchLayer(entryId: entryPoint, query: vector, layer: layer, ef: 1)
                entryPoint = nearest.first.map { $0.id } ?? entryPoint
            }
        }

        for layer in stride(from: min(level, currMaxLevel), through: 0, by: -1) {
            let candidates = searchLayer(entryId: entryPoint, query: vector, layer: layer, ef: efConstruction)
            let neighbors = selectNeighbors(from: candidates, M: layer == 0 ? Mmax0 : Mmax)

            for neighborId in neighbors {
                node.connections[layer].insert(neighborId)
                nodes[neighborId]?.connections[layer].insert(id)

                let maxConn = layer == 0 ? Mmax0 : Mmax
                if nodes[neighborId]!.connections[layer].count > maxConn {
                    trimConnections(nodeId: neighborId, layer: layer, maxConnections: maxConn)
                }
            }

            if !candidates.isEmpty {
                entryPoint = candidates[0].id
            }
        }

        if level > currentMaxLevel {
            currentMaxLevel = level
            entryPointId = id
        }
    }

    func search(query: [Float], limit: Int, efSearch: Int = 50) -> [(id: String, similarity: Float)] {
        lock.lock()
        defer { lock.unlock() }
        return searchLocked(query: query, limit: limit, efSearch: efSearch)
    }

    private func searchLocked(query: [Float], limit: Int, efSearch: Int = 50) -> [(id: String, similarity: Float)] {
        guard !query.isEmpty, let entryId = entryPointId else { return [] }

        var entryPoint = entryId

        for layer in stride(from: currentMaxLevel, to: 0, by: -1) {
            let nearest = searchLayer(entryId: entryPoint, query: query, layer: layer, ef: 1)
            entryPoint = nearest.first.map { $0.id } ?? entryPoint
        }

        let candidates = searchLayer(entryId: entryPoint, query: query, layer: 0, ef: efSearch)

        let normalizedQuery = normalize(query)
        return candidates.prefix(limit).map { candidate in
            let node = nodes[candidate.id]!
            let sim = cosineSimilarity(lhs: normalizedQuery, rhs: node.normalizedVector)
            return (candidate.id, sim)
        }
    }

    func remove(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let node = nodes[id], !node.isDeleted else { return }
        node.isDeleted = true
        deletedCount += 1
        for (layer, connections) in node.connections.enumerated() {
            for neighborId in connections {
                nodes[neighborId]?.connections[layer].remove(id)
            }
        }
        node.connections = node.connections.map { _ in Set<String>() }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        nodes.removeAll()
        entryPointId = nil
        currentMaxLevel = 0
        deletedCount = 0
    }

    func rebuildIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard deletedCount > 0, nodes.count > deletedCount else { return }
        guard Float(deletedCount) / Float(nodes.count) > 0.3 else { return }

        let active = nodes.values.filter { !$0.isDeleted }

        nodes.removeAll()
        entryPointId = nil
        currentMaxLevel = 0
        deletedCount = 0

        for node in active.sorted(by: { $0.level > $1.level }) {
            insertLocked(id: node.id, vector: node.normalizedVector.map { $0 })
        }
    }

    private func searchLayer(entryId: String, query: [Float], layer: Int, ef: Int) -> [(distance: Float, id: String)] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var visited = Set<String>()

        var candidates = BinaryHeap<(distance: Float, id: String)>(sortBy: { $0.distance < $1.distance })
        var results = BinaryHeap<(distance: Float, id: String)>(sortBy: { $0.distance > $1.distance })

        guard let entryNode = nodes[entryId], !entryNode.isDeleted else { return [] }

        let entryDist = cosineDistance(lhs: normalizedQuery, rhs: entryNode.normalizedVector)
        candidates.push((entryDist, entryId))
        results.push((entryDist, entryId))
        visited.insert(entryId)

        while let (cDist, cId) = candidates.pop() {
            guard let furthest = results.peek() else { break }
            if cDist > furthest.distance { break }

            for neighborId in nodes[cId]?.connections[layer] ?? [] {
                guard !visited.contains(neighborId) else { continue }
                visited.insert(neighborId)

                guard let neighborNode = nodes[neighborId], !neighborNode.isDeleted else { continue }

                let neighborDist = cosineDistance(lhs: normalizedQuery, rhs: neighborNode.normalizedVector)
                candidates.push((neighborDist, neighborId))
                results.push((neighborDist, neighborId))

                if results.count > ef {
                    _ = results.pop()
                }
            }
        }

        var sorted = [(distance: Float, id: String)]()
        while let r = results.pop() {
            sorted.append(r)
        }
        return sorted.reversed()
    }

    private func selectNeighbors(from candidates: [(distance: Float, id: String)], M: Int) -> [String] {
        return candidates.prefix(M).map { $0.id }
    }

    private func trimConnections(nodeId: String, layer: Int, maxConnections: Int) {
        guard let node = nodes[nodeId] else { return }
        let currentConnections = Array(node.connections[layer])
        guard currentConnections.count > maxConnections else { return }

        let vector = node.normalizedVector
        let sorted = currentConnections
            .compactMap { id -> (String, Float)? in
                guard let neighbor = nodes[id], !neighbor.isDeleted else { return nil }
                return (id, cosineSimilarity(lhs: vector, rhs: neighbor.normalizedVector))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxConnections)

        let kept = Set(sorted.map { $0.0 })
        let removed = node.connections[layer].subtracting(kept)
        node.connections[layer] = kept

        for removedId in removed {
            nodes[removedId]?.connections[layer].remove(nodeId)
        }
    }

    private func generateLevel() -> Int {
        let r = Float.random(in: 0..<1)
        let level = Int(-log(r) * mL)
        return min(level, 16)
    }

    private func normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return [] }
        return vector.map { $0 / norm }
    }

    private func cosineDistance(lhs: [Float], rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1.0 }
        return 1.0 - zip(lhs, rhs).reduce(into: Float(0)) { $0 += $1.0 * $1.1 }
    }

    private func cosineSimilarity(lhs: [Float], rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0.0 }
        return zip(lhs, rhs).reduce(into: Float(0)) { $0 += $1.0 * $1.1 }
    }
}

private struct BinaryHeap<T> {
    private var elements: [T]
    private let areSorted: (T, T) -> Bool

    init(sortBy: @escaping (T, T) -> Bool) {
        self.elements = []
        self.areSorted = sortBy
    }

    var isEmpty: Bool { elements.isEmpty }
    var count: Int { elements.count }

    func peek() -> T? { elements.first }

    mutating func push(_ value: T) {
        elements.append(value)
        siftUp(from: elements.count - 1)
    }

    mutating func pop() -> T? {
        guard !isEmpty else { return nil }
        elements.swapAt(0, elements.count - 1)
        let value = elements.removeLast()
        siftDown(from: 0)
        return value
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if areSorted(elements[child], elements[parent]) {
                elements.swapAt(child, parent)
                child = parent
            } else { break }
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var candidate = parent

            if left < elements.count && areSorted(elements[left], elements[candidate]) {
                candidate = left
            }
            if right < elements.count && areSorted(elements[right], elements[candidate]) {
                candidate = right
            }
            if candidate == parent { break }
            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
