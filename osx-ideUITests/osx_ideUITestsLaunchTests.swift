import XCTest

@MainActor
final class OSXIDEUITestsLaunchTests: BaseUITestCase {
    func testLaunchScreenshot() {
        _ = launchApp()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
