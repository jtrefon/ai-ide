import Foundation

enum AppRuntimeEnvironment {
    static let launchContext = AppLaunchContext.detect()

    nonisolated(unsafe) static let userDefaults: UserDefaults = {
        let context = launchContext
        guard let testProfilePath = context.testProfilePath, !testProfilePath.isEmpty else {
            return .standard
        }

        let sanitized = testProfilePath
            .replacingOccurrences(of: "[^A-Za-z0-9]", with: "_", options: .regularExpression)
        let suiteName = "tdc.osx-ide.test.\(sanitized)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()
}
