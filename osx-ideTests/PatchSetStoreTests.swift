import XCTest
import SwiftUI
import Combine
@testable import osx_ide

@MainActor
final class PatchSetStoreTests: XCTestCase {
    func testStageWriteAndApplyWritesFile() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_patchset_tests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        await PatchSetStore.shared.setProjectRoot(tempRoot)

        let patchSetId = UUID().uuidString
        try await PatchSetStore.shared.stageWrite(
            patchSetId: patchSetId,
            toolCallId: UUID().uuidString,
            relativePath: "src/Test.swift",
            content: "print(\"hi\")"
        )

        let touched = try await PatchSetStore.shared.applyPatchSet(patchSetId: patchSetId)
        XCTAssertEqual(touched, ["src/Test.swift"])

        let fileURL = tempRoot.appendingPathComponent("src/Test.swift")
        let onDisk = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "print(\"hi\")")
    }

    func testReplaceInFileProposeStagesAndApplyWrites() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_replace_propose_tests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        await PatchSetStore.shared.setProjectRoot(tempRoot)

        let targetURL = tempRoot.appendingPathComponent("src/Test.txt")
        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "hello world".write(to: targetURL, atomically: true, encoding: .utf8)

        let patchSetId = UUID().uuidString
        let toolCallId = UUID().uuidString

        let tool = ReplaceInFileTool(
            fileSystemService: FileSystemService(),
            pathValidator: PathValidator(projectRoot: tempRoot),
            eventBus: EventBus()
        )

        _ = try await tool.execute(arguments: ToolArguments([
            "path": targetURL.path,
            "old_text": "world",
            "new_text": "there",
            "mode": "propose",
            "patch_set_id": patchSetId,
            "_tool_call_id": toolCallId
        ]))

        let unchanged = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertEqual(unchanged, "hello world")

        _ = try await PatchSetStore.shared.applyPatchSet(patchSetId: patchSetId)

        let updated = try String(contentsOf: targetURL, encoding: .utf8)
        XCTAssertEqual(updated, "hello there")
    }

    func testPatchSetApplyCreatesCheckpointAndRestoreRestoresBytes() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_patchset_checkpoint_tests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        await PatchSetStore.shared.setProjectRoot(tempRoot)
        await CheckpointManager.shared.setProjectRoot(tempRoot)

        let fileURL = tempRoot.appendingPathComponent("src/a.txt")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "old".write(to: fileURL, atomically: true, encoding: .utf8)

        let patchSetId = UUID().uuidString
        try await PatchSetStore.shared.stageWrite(
            patchSetId: patchSetId,
            toolCallId: UUID().uuidString,
            relativePath: "src/a.txt",
            content: "new"
        )

        let tool = PatchSetApplyTool(eventBus: EventBus(), projectRoot: tempRoot)
        _ = try await tool.execute(arguments: ToolArguments(["patch_set_id": patchSetId]))

        let applied = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(applied, "new")

        let checkpointIds = await CheckpointManager.shared.listCheckpointIds()
        XCTAssertEqual(checkpointIds.count, 1)

        if let checkpointId = checkpointIds.first {
            _ = try await CheckpointManager.shared.restoreCheckpoint(checkpointId: checkpointId)
        }

        let restored = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(restored, "old")
    }

    func testClearPatchSetRemovesDirectory() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("osx_ide_patchset_tests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        await PatchSetStore.shared.setProjectRoot(tempRoot)

        let patchSetId = UUID().uuidString
        try await PatchSetStore.shared.stageWrite(
            patchSetId: patchSetId,
            toolCallId: UUID().uuidString,
            relativePath: "a.txt",
            content: "a"
        )

        let dir = await PatchSetStore.shared.patchSetDirectory(patchSetId: patchSetId)
        XCTAssertNotNil(dir)
        if let dir {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        }

        try await PatchSetStore.shared.clearPatchSet(patchSetId: patchSetId)
        if let dir {
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        }
    }
}
