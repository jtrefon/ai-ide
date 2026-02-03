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
                TextField(NSLocalizedString("language_modules.search.placeholder", comment: ""), text: $searchText)
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
                        title: NSLocalizedString("language_modules.card.title", comment: ""),
                        subtitle: NSLocalizedString("language_modules.card.subtitle", comment: "")
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if filteredLanguages.isEmpty {
                                Text(String(
                                    format: NSLocalizedString("language_modules.empty", comment: ""),
                                    searchText
                                ))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                            } else {
                                ForEach(filteredLanguages, id: \.self) { language in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(language.rawValue.capitalized)
                                                .font(.headline)
                                            Text(NSLocalizedString("language_modules.feature_summary", comment: ""))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            if let module = moduleManager.getModule(for: language) {
                                                Text(
                                                    String(
                                                        format: NSLocalizedString(
                                                            "language_modules.extensions",
                                                            comment: ""
                                                        ),
                                                        module.fileExtensions.joined(separator: ", ")
                                                    )
                                                )
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.blue.opacity(0.8))
                                            }
                                        }

                                        Spacer()

                                        Toggle(
                                            "",
                                            isOn: Binding(
                                                get: { moduleManager.isEnabled(language) },
                                                set: { enabled in
                                                    moduleManager.toggleModule(
                                                        language,
                                                        enabled: enabled
                                                    )
                                                }
                                            )
                                        )
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
                        title: NSLocalizedString("language_modules.performance.title", comment: ""),
                        subtitle: NSLocalizedString("language_modules.performance.subtitle", comment: "")
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text(NSLocalizedString("language_modules.performance.detail", comment: ""))
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
