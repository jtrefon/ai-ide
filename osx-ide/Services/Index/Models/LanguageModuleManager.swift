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
    private let settingsStore: SettingsStore
    
    private init() {
        settingsStore = SettingsStore(userDefaults: .standard)
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
    
    public func register(_ module: LanguageModule) {
        allModules[module.id] = module
        updateEnabledModules()
    }
    
    public func getModule(for language: CodeLanguage) -> LanguageModule? {
        return enabledModules[language]
    }
    
    public func getModule(forExtension ext: String) -> LanguageModule? {
        let ext = ext.lowercased()
        return enabledModules.values.first { $0.fileExtensions.contains(ext) }
    }
    
    public func isEnabled(_ language: CodeLanguage) -> Bool {
        return enabledModules[language] != nil
    }
    
    public func toggleModule(_ language: CodeLanguage, enabled: Bool) {
        var enabledLangs = settingsStore.stringArray(forKey: AppConstants.Storage.enabledLanguageModulesKey) ?? allModules.keys.map { $0.rawValue }
        
        if enabled {
            if !enabledLangs.contains(language.rawValue) {
                enabledLangs.append(language.rawValue)
            }
        } else {
            enabledLangs.removeAll { $0 == language.rawValue }
        }
        
        settingsStore.set(enabledLangs, forKey: AppConstants.Storage.enabledLanguageModulesKey)
        updateEnabledModules()
    }
    
    private func setupInitialEnabledState() {
        let allLangs = allModules.keys.map { $0.rawValue }
        if let stored = settingsStore.stringArray(forKey: AppConstants.Storage.enabledLanguageModulesKey) {
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
                settingsStore.set(updated, forKey: AppConstants.Storage.enabledLanguageModulesKey)
            }
        } else {
            settingsStore.set(allLangs, forKey: AppConstants.Storage.enabledLanguageModulesKey)
        }
        updateEnabledModules()
    }
    
    private func updateEnabledModules() {
        let enabledLangs = settingsStore.stringArray(forKey: AppConstants.Storage.enabledLanguageModulesKey) ?? allModules.keys.map { $0.rawValue }
        enabledModules = allModules.filter { enabledLangs.contains($0.key.rawValue) }
    }
    
    public var availableLanguages: [CodeLanguage] {
        return allModules.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
