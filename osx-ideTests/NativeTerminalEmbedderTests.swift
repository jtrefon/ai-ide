import XCTest
@testable import osx_ide

@MainActor
final class NativeTerminalEmbedderTests: XCTestCase {
    private final class MockShellManager: ShellManaging {
        var delegate: ShellManagerDelegate?
        private(set) var sentInputs: [String] = []

        func start(in directory: URL?) {}

        func sendInput(_ text: String) {
            sentInputs.append(text)
        }

        func interrupt() {}

        func terminate() {}
    }

    func testEnterSendsNewlineToShell() {
        let mockShell = MockShellManager()
        let embedder = NativeTerminalEmbedder(shellManager: mockShell)

        let textView = NSTextView()
        _ = embedder.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(mockShell.sentInputs, ["\n"])
    }
}
