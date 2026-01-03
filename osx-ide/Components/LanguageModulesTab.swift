//
//  LanguageModulesTab.swift
//  osx-ide
//
//  Created by Cascade on 02/01/2026.
//

import SwiftUI

struct LanguageModulesTab: View {
    @ObservedObject var moduleManager = LanguageModuleManager.shared
    @State private var searchText = ""
    
    var filteredLanguages: [CodeLanguage] {
        if searchText.isEmpty {
            return moduleManager.availableLanguages
        } else {
            return moduleManager.availableLanguages.filter { 
                $0.rawValue.localizedCaseInsensitiveContains(searchText) 
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search modules...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 20) {
                    SettingsCard(
                        title: "Language Modules",
                        subtitle: "Enable or disable language-specific features for better performance."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if filteredLanguages.isEmpty {
                                Text("No modules found matching '\(searchText)'")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(filteredLanguages, id: \.self) { language in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(language.rawValue.capitalized)
                                                .font(.headline)
                                            Text("Syntax coloring, symbol extraction, and IntelliSense.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            
                                            if let module = moduleManager.getModule(for: language) {
                                                Text("Extensions: \(module.fileExtensions.joined(separator: ", "))")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.blue.opacity(0.8))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Toggle("", isOn: Binding(
                                            get: { moduleManager.isEnabled(language) },
                                            set: { enabled in moduleManager.toggleModule(language, enabled: enabled) }
                                        ))
                                        .toggleStyle(.switch)
                                    }
                                    
                                    if language != filteredLanguages.last {
                                        Divider()
                                            .opacity(0.1)
                                    }
                                }
                            }
                        }
                    }
                    
                    SettingsCard(
                        title: "Performance Note",
                        subtitle: "Disabling unused modules reduces memory usage and speeds up indexing."
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("When a module is disabled, files of that type will still be viewable but will not have syntax highlighting or symbol navigation.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}
