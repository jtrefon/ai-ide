import Foundation
import Combine

class PersistenceService {
    enum Keys {
        static let currentDirectoryPath = "AppState.currentDirectoryPath"
        static let selectedFilePath = "AppState.selectedFilePath"
        static let currentDirectoryBookmark = "AppState.currentDirectoryBookmark"
        static let selectedFileBookmark = "AppState.selectedFileBookmark"
        static let isSidebarVisible = "AppState.isSidebarVisible"
        static let isTerminalVisible = "AppState.isTerminalVisible"
        static let isAIPanelVisible = "AppState.isAIPanelVisible"
        static let explorerExpandedRelativePaths = "AppState.explorerExpandedRelativePaths"
        static let explorerSelectedRelativePath = "AppState.explorerSelectedRelativePath"
    }
    
    private let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    func save<T>(_ value: T, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func load<T>(forKey key: String) -> T? {
        return userDefaults.object(forKey: key) as? T
    }
    
    func remove(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
    func saveBookmark(for url: URL, forKey key: String) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            userDefaults.set(data, forKey: key)
        }
    }
    
    func restoreURL(fromBookmarkKey bookmarkKey: String, pathKey: String) -> URL? {
        if let data = userDefaults.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        if let path = userDefaults.string(forKey: pathKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }
}
