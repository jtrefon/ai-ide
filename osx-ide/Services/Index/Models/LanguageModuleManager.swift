//
//  LanguageModuleManager.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import Foundation
import AppKit
import Combine

/// Manages registration and activation of language modules.
@MainActor
public final class LanguageModuleManager: ObservableObject {
    public static let shared = LanguageModuleManager()

    @Published private(set) var enabledModules: [CodeLanguage: LanguageModule] = [:]
    private var allModules: [CodeLanguage: LanguageModule] = [:]
    private var disabledCapabilitiesByLanguage: [CodeLanguage: Set<LanguageModuleCapability>] = [:]
    private let settingsStore: SettingsStore

    private init() {
        settingsStore = SettingsStore(userDefaults: AppRuntimeEnvironment.userDefaults)
        // Register default modules
        register(SwiftModule())
        register(JavaScriptModule())
        register(TypeScriptModule())
        register(PythonModule())
        register(HTMLModule())
        register(CSSModule())
        register(JSONModule())

        setupInitialEnabledState()
    }

    private func loadDisabledCapabilities() {
        guard let stored = settingsStore.dictionary(forKey: AppConstantsStorage.disabledLanguageModuleCapabilitiesKey) else {
            disabledCapabilitiesByLanguage = [:]
            return
        }

        var mapped: [CodeLanguage: Set<LanguageModuleCapability>] = [:]
        for (languageRaw, value) in stored {
            guard let language = CodeLanguage(rawValue: languageRaw) else { continue }
            guard let capabilityNames = value as? [String] else { continue }

            let capabilities = capabilityNames.compactMap { LanguageModuleCapability(rawValue: $0) }
            mapped[language] = Set(capabilities)
        }

        disabledCapabilitiesByLanguage = mapped
    }

    private func persistDisabledCapabilities() {
        var serialized: [String: [String]] = [:]
        for (language, capabilities) in disabledCapabilitiesByLanguage {
            serialized[language.rawValue] = capabilities.map(\.rawValue).sorted()
        }
        settingsStore.set(serialized, forKey: AppConstantsStorage.disabledLanguageModuleCapabilitiesKey)
    }

    public func register(_ module: LanguageModule) {
        allModules[module.id] = module
        updateEnabledModules()
    }

    public func getModule(for language: CodeLanguage) -> LanguageModule? {
        return enabledModules[language]
    }

    public func getHighlightModule(for language: CodeLanguage) -> LanguageModule? {
        guard let module = enabledModules[language] else { return nil }
        guard isCapabilityEnabled(.highlight, for: language) else { return nil }
        return module
    }

    public func getModule(forExtension ext: String) -> LanguageModule? {
        let ext = ext.lowercased()
        return enabledModules.values.first { $0.fileExtensions.contains(ext) }
    }

    public func getHighlightModule(forExtension ext: String) -> LanguageModule? {
        let normalizedExtension = ext.lowercased()
        guard let module = enabledModules.values.first(where: { $0.fileExtensions.contains(normalizedExtension) }) else {
            return nil
        }
        guard isCapabilityEnabled(.highlight, for: module.id) else { return nil }
        return module
    }

    public func isEnabled(_ language: CodeLanguage) -> Bool {
        return enabledModules[language] != nil
    }

    public func toggleModule(_ language: CodeLanguage, enabled: Bool) {
        var enabledLangs = settingsStore.stringArray(
            forKey: AppConstantsStorage.enabledLanguageModulesKey
        ) ?? allModules.keys.map { $0.rawValue }

        if enabled {
            if !enabledLangs.contains(language.rawValue) {
                enabledLangs.append(language.rawValue)
            }
        } else {
            enabledLangs.removeAll { $0 == language.rawValue }
        }

        settingsStore.set(enabledLangs, forKey: AppConstantsStorage.enabledLanguageModulesKey)
        updateEnabledModules()
    }

    public func isCapabilityEnabled(_ capability: LanguageModuleCapability, for language: CodeLanguage) -> Bool {
        guard let module = allModules[language] else { return false }
        guard module.capabilities.contains(capability) else { return false }
        let disabledCapabilities = disabledCapabilitiesByLanguage[language] ?? []
        return !disabledCapabilities.contains(capability)
    }

    public func toggleCapability(
        _ capability: LanguageModuleCapability,
        for language: CodeLanguage,
        enabled: Bool
    ) {
        guard let module = allModules[language], module.capabilities.contains(capability) else { return }

        var disabledCapabilities = disabledCapabilitiesByLanguage[language] ?? []
        if enabled {
            disabledCapabilities.remove(capability)
        } else {
            disabledCapabilities.insert(capability)
        }
        disabledCapabilitiesByLanguage[language] = disabledCapabilities
        persistDisabledCapabilities()
    }

    private func setupInitialEnabledState() {
        loadDisabledCapabilities()

        let allLangs = allModules.keys.map { $0.rawValue }
        if let stored = settingsStore.stringArray(forKey: AppConstantsStorage.enabledLanguageModulesKey) {
            // Ensure any newly added modules are also enabled if they weren't in the stored list
            var updated = stored
            var changed = false
            for lang in allLangs {
                if !updated.contains(lang) {
                    updated.append(lang)
                    changed = true
                }
            }
            if changed {
                settingsStore.set(updated, forKey: AppConstantsStorage.enabledLanguageModulesKey)
            }
        } else {
            settingsStore.set(allLangs, forKey: AppConstantsStorage.enabledLanguageModulesKey)
        }
        updateEnabledModules()
    }

    private func updateEnabledModules() {
        let enabledLangs = settingsStore.stringArray(
            forKey: AppConstantsStorage.enabledLanguageModulesKey
        ) ?? allModules.keys.map { $0.rawValue }
        enabledModules = allModules.filter { enabledLangs.contains($0.key.rawValue) }
    }

    public var availableLanguages: [CodeLanguage] {
        return allModules.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
