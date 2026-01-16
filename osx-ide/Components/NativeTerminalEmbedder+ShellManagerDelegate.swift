import Foundation

// MARK: - ShellManagerDelegate
extension NativeTerminalEmbedder: ShellManagerDelegate {
    func shellManager(_ manager: ShellManager, didProduceOutput output: String) {
        appendOutput(output)
    }

    func shellManager(_ manager: ShellManager, didFailWithError error: String) {
        self.errorMessage = error
    }

    func shellManagerDidTerminate(_ manager: ShellManager) {
        appendOutput("\n[Process terminated]\n")
    }
}
