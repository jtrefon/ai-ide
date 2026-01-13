//
//  FileTreeIsolationTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
import AppKit
import SwiftUI
@testable import osx_ide

@MainActor
final class FileTreeIsolationTests: XCTestCase {
    
    var dataSource: FileTreeDataSource!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        dataSource = FileTreeDataSource()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        dataSource = nil
        try await super.tearDown()
    }
    
    func testRapidRootChange() throws {
        // Create dummy files
        for i in 0..<100 {
            let fileURL = tempDirectory.appendingPathComponent("file_\(i).txt")
            try? "content".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Rapidly change root/search to provoke race conditions
        for i in 0..<50 {
            if i % 2 == 0 {
                self.dataSource.setRootURL(self.tempDirectory)
            } else {
                self.dataSource.setSearchQuery("file")
            }
        }
    }
    
    func testDataSourceConsistency() throws {
        // Setup
        let folderA = tempDirectory.appendingPathComponent("FolderA")
        try? FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        let fileA = folderA.appendingPathComponent("FileA.txt")
        try? "content".write(to: fileA, atomically: true, encoding: .utf8)
        
        dataSource.setRootURL(tempDirectory)

        // Allow any pending work to settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let outlineView = NSOutlineView()
        let count = dataSource.outlineView(outlineView, numberOfChildrenOfItem: nil)
        XCTAssertTrue(count > 0, "Should have loaded children")

        // Check if root is correct
        let child = dataSource.outlineView(outlineView, child: 0, ofItem: nil)
        XCTAssertNotNil(child as? FileTreeItem)
    }

    func testChildOfUnexpectedItemDoesNotCrash() throws {
        dataSource.setRootURL(tempDirectory)
        let outlineView = NSOutlineView()
        let child = dataSource.outlineView(outlineView, child: 0, ofItem: NSObject())
        XCTAssertNotNil(child)
    }

    func testNestedDirectoryChildrenCanBeLoadedSynchronously() throws {
        let folderA = tempDirectory.appendingPathComponent("FolderA")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        let nested = folderA.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = nested.appendingPathComponent("hello.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)

        dataSource.setRootURL(tempDirectory)

        let outlineView = NSOutlineView()
        let rootChildCount = dataSource.outlineView(outlineView, numberOfChildrenOfItem: nil as Any?)
        XCTAssertGreaterThan(rootChildCount, 0)

        let folderAItemAny = dataSource.outlineView(outlineView, child: 0, ofItem: nil as Any?)
        guard let folderAItem = folderAItemAny as? FileTreeItem else {
            XCTFail("Expected FileTreeItem")
            return
        }

        let folderAChildrenCount = dataSource.outlineView(outlineView, numberOfChildrenOfItem: folderAItem)
        XCTAssertGreaterThan(folderAChildrenCount, 0)
    }

    func testOutlineCellRenderingForNestedItemsDoesNotCrash() throws {
        let folderA = tempDirectory.appendingPathComponent("FolderA")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        let folderB = folderA.appendingPathComponent("FolderB")
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let fileB = folderB.appendingPathComponent("file.txt")
        try "content".write(to: fileB, atomically: true, encoding: .utf8)

        let expanded = Binding<Set<String>>(get: { [] }, set: { _ in })
        let selected = Binding<String?>(get: { nil }, set: { _ in })
        let coordinator = ModernFileTreeCoordinator(
            configuration: ModernFileTreeCoordinator.Configuration(
                expandedRelativePaths: expanded,
                selectedRelativePath: selected,
                onOpenFile: { _ in },
                onCreateFile: { _, _ in },
                onCreateFolder: { _, _ in },
                onDeleteItem: { _ in },
                onRenameItem: { _, _ in },
                onRevealInFinder: { _ in }
            )
        )

        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = coordinator.dataSource
        outlineView.delegate = coordinator
        coordinator.attach(outlineView: outlineView)

        coordinator.dataSource.setRootURL(tempDirectory)
        outlineView.reloadData()

        let rootChildCount = coordinator.dataSource.outlineView(outlineView, numberOfChildrenOfItem: nil as Any?)
        XCTAssertGreaterThan(rootChildCount, 0)

        for i in 0..<min(rootChildCount, 5) {
            let childAny = coordinator.dataSource.outlineView(outlineView, child: i, ofItem: nil as Any?)
            _ = coordinator.outlineView(outlineView, viewFor: column, item: childAny)

            if coordinator.dataSource.outlineView(outlineView, isItemExpandable: childAny) {
                let nestedCount = coordinator.dataSource.outlineView(outlineView, numberOfChildrenOfItem: childAny)
                for j in 0..<min(nestedCount, 5) {
                    let nestedAny = coordinator.dataSource.outlineView(outlineView, child: j, ofItem: childAny)
                    _ = coordinator.outlineView(outlineView, viewFor: column, item: nestedAny)
                }
            }
        }
    }

    func testSearchTypingDoesNotCrashAndProducesResults() throws {
        for i in 0..<50 {
            let fileURL = tempDirectory.appendingPathComponent("file_\(i).txt")
            try "content".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let expanded = Binding<Set<String>>(get: { [] }, set: { _ in })
        let selected = Binding<String?>(get: { nil }, set: { _ in })
        let coordinator = ModernFileTreeCoordinator(
            configuration: ModernFileTreeCoordinator.Configuration(
                expandedRelativePaths: expanded,
                selectedRelativePath: selected,
                onOpenFile: { _ in },
                onCreateFile: { _, _ in },
                onCreateFolder: { _, _ in },
                onDeleteItem: { _ in },
                onRenameItem: { _, _ in },
                onRevealInFinder: { _ in }
            )
        )

        let dataSource = coordinator.dataSource
        dataSource.setRootURL(tempDirectory)
        dataSource.setSearchQuery("")
        
        coordinator.update(
            rootURL: tempDirectory,
            parameters: ModernFileTreeCoordinator.UpdateParameters(
                searchQuery: "",
                showHiddenFiles: false,
                refreshToken: 0,
                fontSize: 13,
                fontFamily: "SF Mono"
            )
        )
        coordinator.update(
            rootURL: tempDirectory,
            parameters: ModernFileTreeCoordinator.UpdateParameters(
                searchQuery: "f",
                showHiddenFiles: false,
                refreshToken: 0,
                fontSize: 13,
                fontFamily: "SF Mono"
            )
        )
        coordinator.update(
            rootURL: tempDirectory,
            parameters: ModernFileTreeCoordinator.UpdateParameters(
                searchQuery: "fi",
                showHiddenFiles: false,
                refreshToken: 0,
                fontSize: 13,
                fontFamily: "SF Mono"
            )
        )
        coordinator.update(
            rootURL: tempDirectory,
            parameters: ModernFileTreeCoordinator.UpdateParameters(
                searchQuery: "file_1",
                showHiddenFiles: false,
                refreshToken: 0,
                fontSize: 13,
                fontFamily: "SF Mono"
            )
        )

        let outlineView = NSOutlineView()
        var childCount = 0
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            childCount = coordinator.dataSource.outlineView(outlineView, numberOfChildrenOfItem: nil as Any?)
            if childCount > 0 { break }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertGreaterThan(childCount, 0)
    }
}
