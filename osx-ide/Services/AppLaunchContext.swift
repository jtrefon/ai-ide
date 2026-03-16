import Foundation

enum AppLaunchMode: Equatable {
    case app
    case unitTest
    case uiTest
}

struct AppLaunchContext: Equatable {
    let mode: AppLaunchMode
    let isTesting: Bool
    let isUITesting: Bool
    let testProfilePath: String?
    let disableHeavyInit: Bool
    let productionParityHarness: Bool

    static func detect(
        processInfo: ProcessInfo = .processInfo,
        environmentOverride: [String: String]? = nil
    ) -> AppLaunchContext {
        let env = environmentOverride ?? processInfo.environment
        let hasXCTestConfig = env["XCTestConfigurationFilePath"] != nil
        let isUITesting = env[TestLaunchKeys.xcuiTesting] == "1"
        let mode: AppLaunchMode

        if isUITesting {
            mode = .uiTest
        } else if hasXCTestConfig {
            mode = .unitTest
        } else {
            mode = .app
        }

        let disableHeavyInit = env[TestLaunchKeys.disableHeavyInit] == "1" || isUITesting
        let productionParityHarness = env[TestLaunchKeys.productionParityHarness] == "1"
        let testProfilePath = env[TestLaunchKeys.testProfileDir]

        return AppLaunchContext(
            mode: mode,
            isTesting: hasXCTestConfig || isUITesting,
            isUITesting: isUITesting,
            testProfilePath: testProfilePath,
            disableHeavyInit: disableHeavyInit,
            productionParityHarness: productionParityHarness
        )
    }
}
