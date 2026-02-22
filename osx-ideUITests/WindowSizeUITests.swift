import XCTest

@MainActor
final class WindowSizeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }
    
    func testWindowSizeDoesNotExceedScreen() throws {
        let app = XCUIApplication()
        app.launch()
        
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))
        
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        let windowFrame = mainWindow.frame
        
        XCTAssertLessThanOrEqual(windowFrame.width, screenBounds.width)
        XCTAssertLessThanOrEqual(windowFrame.height, screenBounds.height)
    }
}
