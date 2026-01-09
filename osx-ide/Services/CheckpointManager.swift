import Foundation
import Darwin

public actor CheckpointManager {
    public static let shared = CheckpointManager()

    private var projectRoot: URL?

    public func setProjectRoot(_ root: URL) {
        self.projectRoot = root
    }

    public func checkpointsRootDirectory() -> URL? {
        projectRoot?
            .appendingPathComponent(".ide", isDirectory: true)
            .appendingPathComponent("checkpoints", isDirectory: true)
    }

    public func checkpointDirectory(checkpointId: String) -> URL? {
        checkpointsRootDirectory()?.appendingPathComponent(checkpointId, isDirectory: true)
    }

    private func manifestURL(checkpointId: String) -> URL? {
        checkpointDirectory(checkpointId: checkpointId)?.appendingPathComponent("manifest.json")
    }

    public func listCheckpointIds() -> [String] {
        guard let root = checkpointsRootDirectory() else { return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted()
    }

    public func loadManifest(checkpointId: String) -> CheckpointManifest? {
        guard let url = manifestURL(checkpointId: checkpointId) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CheckpointManifest.self, from: data)
    }

    public func createCheckpoint(relativePaths: [String]) throws -> String {
        guard let root = projectRoot else { throw AppError.aiServiceError("CheckpointManager missing project root") }

        let checkpointId = UUID().uuidString
        guard let checkpointDir = checkpointDirectory(checkpointId: checkpointId) else {
            throw AppError.aiServiceError("CheckpointManager missing checkpoint directory")
        }

        try FileManager.default.createDirectory(at: checkpointDir, withIntermediateDirectories: true)

        var entries: [CheckpointEntry] = []
        entries.reserveCapacity(relativePaths.count)

        for relativePath in relativePaths {
            let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.isEmpty { continue }

            let sourceURL = root.appendingPathComponent(normalized)
            let existed = FileManager.default.fileExists(atPath: sourceURL.path)

            if !existed {
                entries.append(CheckpointEntry(relativePath: normalized, existed: false, stagedRelativeBackupPath: nil))
                continue
            }

            let backupURL = checkpointDir.appendingPathComponent("files", isDirectory: true).appendingPathComponent(normalized)
            try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            try copyFile(source: sourceURL, destination: backupURL)
            entries.append(CheckpointEntry(relativePath: normalized, existed: true, stagedRelativeBackupPath: "files/\(normalized)"))
        }

        let manifest = CheckpointManifest(id: checkpointId, createdAt: Date(), entries: entries)
        let data = try JSONEncoder().encode(manifest)
        if let manifestURL = manifestURL(checkpointId: checkpointId) {
            try data.write(to: manifestURL, options: [.atomic])
        }

        return checkpointId
    }

    public func restoreCheckpoint(checkpointId: String) throws -> [String] {
        guard let root = projectRoot else { throw AppError.aiServiceError("CheckpointManager missing project root") }
        guard let checkpointDir = checkpointDirectory(checkpointId: checkpointId) else {
            throw AppError.aiServiceError("CheckpointManager missing checkpoint directory")
        }
        guard let manifest = loadManifest(checkpointId: checkpointId) else {
            throw AppError.aiServiceError("Checkpoint not found: \(checkpointId)")
        }

        var restored: [String] = []
        restored.reserveCapacity(manifest.entries.count)

        func restoreExisting(_ entry: CheckpointEntry) throws -> Bool {
            guard let rel = entry.stagedRelativeBackupPath else { return false }
            let backupURL = checkpointDir.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: backupURL.path) else { return false }

            let targetURL = root.appendingPathComponent(entry.relativePath)
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copyFile(source: backupURL, destination: targetURL)
            return true
        }

        func deleteIfPresent(_ entry: CheckpointEntry) throws -> Bool {
            let targetURL = root.appendingPathComponent(entry.relativePath)
            guard FileManager.default.fileExists(atPath: targetURL.path) else { return false }
            try FileManager.default.removeItem(at: targetURL)
            return true
        }

        for entry in manifest.entries {
            if entry.existed {
                if try restoreExisting(entry) {
                    restored.append(entry.relativePath)
                }
            } else {
                if try deleteIfPresent(entry) {
                    restored.append(entry.relativePath)
                }
            }
        }

        return restored
    }

    public func deleteCheckpoint(checkpointId: String) throws {
        guard let dir = checkpointDirectory(checkpointId: checkpointId) else { return }
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func copyFile(source: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let result = copyfile(source.path, destination.path, nil, copyfile_flags_t(COPYFILE_CLONE))
        if result == 0 {
            return
        }

        try FileManager.default.copyItem(at: source, to: destination)
    }
}
