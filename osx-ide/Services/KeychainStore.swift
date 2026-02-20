//
//  KeychainStore.swift
//  osx-ide
//
//  Stores credentials securely in the macOS Keychain without requiring authentication on every read.
//

import Foundation
import Security

final class KeychainStore {
    enum KeychainStoreError: Error {
        case unexpectedStatus(OSStatus)
        case invalidItemFormat
    }

    private let service: String

    init(service: String) {
        self.service = service
    }

    /// Reads a password from the keychain without requiring authentication.
    /// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly for automatic access when unlocked.
    func readPassword(account: String) throws -> String? {
        // Simple query without LAContext - no authentication required
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainStoreError.invalidItemFormat
        }
        return String(data: data, encoding: .utf8)
    }

    /// Saves a password to the keychain without requiring authentication on future reads.
    /// Uses kSecAttrAccessibleWhenUnlockedThisDeviceOnly - accessible when Mac is unlocked.
    func savePassword(_ password: String, account: String) throws {
        let data = Data(password.utf8)

        // First try to update existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        
        // If item doesn't exist, create new one
        if updateStatus == errSecItemNotFound {
            // Use kSecAttrAccessibleWhenUnlockedThisDeviceOnly - no authentication required
            // when the Mac is unlocked. This is appropriate for API keys.
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(addStatus)
            }
            return
        }
        
        throw KeychainStoreError.unexpectedStatus(updateStatus)
    }

    func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            return
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
