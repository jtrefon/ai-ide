import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let userDefaults: UserDefaults
    let aiService: any AIService

    init(userDefaults: UserDefaults = .standard, aiService: any AIService = SampleAIService()) {
        self.userDefaults = userDefaults
        self.aiService = aiService
    }
}
