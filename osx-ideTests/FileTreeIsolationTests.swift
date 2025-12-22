//
//  FileTreeIsolationTests.swift
//  osx-ideTests
//
//  Created by Jack Trefon on 21/12/2025.
//

import XCTest
import AppKit
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
    
    func testRapidRootChange() async throws {
        // Create dummy files
        for i in 0..<100 {
            let fileURL = tempDirectory.appendingPathComponent("file_\(i).txt")
            try? "content".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        let expectation = expectation(description: "Rapid reload completed")
        expectation.expectedFulfillmentCount = 50
        
        // Rapidly change root/search to provoke race conditions
        for i in 0..<50 {
            if i % 2 == 0 {
                self.dataSource.setRootURL(self.tempDirectory)
            } else {
                self.dataSource.setSearchQuery("file")
            }
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testDataSourceConsistency() async throws {
        // Setup
        let folderA = tempDirectory.appendingPathComponent("FolderA")
        try? FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        let fileA = folderA.appendingPathComponent("FileA.txt")
        try? "content".write(to: fileA, atomically: true, encoding: .utf8)
        
        dataSource.setRootURL(tempDirectory)
        
        // Wait for potential async loading
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        
        let outlineView = NSOutlineView()
        let count = dataSource.outlineView(outlineView, numberOfChildrenOfItem: nil)
        XCTAssertTrue(count > 0, "Should have loaded children")
        
        // Check if root is correct
        let child = dataSource.outlineView(outlineView, child: 0, ofItem: nil)
        XCTAssertNotNil(child as? FileTreeItem)
    }
}
