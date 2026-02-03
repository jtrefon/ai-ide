import Foundation

// MARK: - ShellManagerDelegate
extension NativeTerminalEmbedder: ShellManagerDelegate {
    func shellManager(_ _: ShellManager, didProduceOutput output: String) {
        appendOutput(output)
    }

    func shellManager(_ _: ShellManager, didFailWithError error: String) {
        self.errorMessage = error
    }

    func shellManagerDidTerminate(_ _: ShellManager) {
        appendOutput("\n[Process terminated]\n")
    }
}
