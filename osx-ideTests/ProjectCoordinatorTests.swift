import XCTest
@testable import osx_ide

final class ProjectCoordinatorTests: XCTestCase {
    func testInitialProjectReindexRunsWhenDatabaseIsMissing() {
        XCTAssertTrue(
            ProjectCoordinator.shouldRunInitialProjectReindex(
                dbExists: false,
                hasPersistedIndexData: false
            )
        )
    }

    func testInitialProjectReindexSkipsWhenPersistedIndexDataExists() {
        XCTAssertFalse(
            ProjectCoordinator.shouldRunInitialProjectReindex(
                dbExists: true,
                hasPersistedIndexData: true
            )
        )
    }

    func testInitialProjectReindexRunsWhenDatabaseExistsButHasNoIndexedData() {
        XCTAssertTrue(
            ProjectCoordinator.shouldRunInitialProjectReindex(
                dbExists: true,
                hasPersistedIndexData: false
            )
        )
    }
}
