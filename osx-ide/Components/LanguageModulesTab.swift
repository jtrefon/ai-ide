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
        Form {
            Section {
                if filteredLanguages.isEmpty {
                    Text(String(
                        format: NSLocalizedString("language_modules.empty", comment: ""),
                        searchText
                    ))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
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
                                    Text(module.fileExtensions.joined(separator: ", "))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { moduleManager.isEnabled(language) },
                                set: { moduleManager.toggleModule(language, enabled: $0) }
                            ))
                            .toggleStyle(.switch)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("language_modules.card.title", comment: ""))
            } footer: {
                Text(NSLocalizedString("language_modules.card.subtitle", comment: ""))
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text(NSLocalizedString("language_modules.performance.detail", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(NSLocalizedString("language_modules.performance.title", comment: ""))
            } footer: {
                Text(NSLocalizedString("language_modules.performance.subtitle", comment: ""))
            }
        }
        .formStyle(.grouped)
    }
}
