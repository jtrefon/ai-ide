import Foundation
import Combine

final class SettingsStore {
    private let userDefaults: UserDefaults
    private let changesSubject = PassthroughSubject<String, Never>()

    var changes: AnyPublisher<String, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: key)
    }

    func double(forKey key: String) -> Double {
        userDefaults.double(forKey: key)
    }

    func int(forKey key: String, default defaultValue: Int) -> Int {
        if let value = userDefaults.object(forKey: key) as? Int {
            return value
        }
        if let value = userDefaults.object(forKey: key) as? Double {
            return Int(value)
        }
        if let value = userDefaults.object(forKey: key) as? String, let intValue = Int(value) {
            return intValue
        }
        return defaultValue
    }

    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        userDefaults.object(forKey: key) as? Bool ?? defaultValue
    }

    func stringArray(forKey key: String) -> [String]? {
        userDefaults.stringArray(forKey: key)
    }

    func set(_ value: Any?, forKey key: String) {
        userDefaults.set(value, forKey: key)
        changesSubject.send(key)
    }

    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
        changesSubject.send(key)
    }
}
