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
    
    private init() {
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
        var enabledLangs = UserDefaults.standard.stringArray(forKey: "EnabledLanguageModules") ?? allModules.keys.map { $0.rawValue }
        
        if enabled {
            if !enabledLangs.contains(language.rawValue) {
                enabledLangs.append(language.rawValue)
            }
        } else {
            enabledLangs.removeAll { $0 == language.rawValue }
        }
        
        UserDefaults.standard.set(enabledLangs, forKey: "EnabledLanguageModules")
        updateEnabledModules()
    }
    
    private func setupInitialEnabledState() {
        if UserDefaults.standard.object(forKey: "EnabledLanguageModules") == nil {
            let allLangs = allModules.keys.map { $0.rawValue }
            UserDefaults.standard.set(allLangs, forKey: "EnabledLanguageModules")
        }
        updateEnabledModules()
    }
    
    private func updateEnabledModules() {
        let enabledLangs = UserDefaults.standard.stringArray(forKey: "EnabledLanguageModules") ?? []
        enabledModules = allModules.filter { enabledLangs.contains($0.key.rawValue) }
    }
    
    public var availableLanguages: [CodeLanguage] {
        return allModules.keys.sorted { $0.rawValue < $1.rawValue }
    }
}
