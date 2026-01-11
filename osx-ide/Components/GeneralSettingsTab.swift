//
//  GeneralSettingsTab.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var ui: UIStateManager
    
    private let fontFamilies = [
        AppConstants.Editor.defaultFontFamily,
        "Menlo",
        "JetBrains Mono",
        "Fira Code",
        "Source Code Pro",
        "Courier New"
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Settings.sectionSpacing) {
                SettingsCard(
                    title: NSLocalizedString("settings.appearance.title", comment: ""),
                    subtitle: NSLocalizedString("settings.appearance.subtitle", comment: "")
                ) {
                    SettingsRow(
                        title: NSLocalizedString("settings.appearance.theme.title", comment: ""),
                        subtitle: NSLocalizedString("settings.appearance.theme.subtitle", comment: ""),
                        systemImage: "paintpalette"
                    ) {
                        Picker("", selection: themeBinding) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                Text(theme.displayName)
                                    .tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: AppConstants.Settings.pickerWideWidth)
                        .accessibilityIdentifier("Settings.Theme")
                    }
                }
                
                SettingsCard(
                    title: NSLocalizedString("settings.editor.title", comment: ""),
                    subtitle: NSLocalizedString("settings.editor.subtitle", comment: "")
                ) {
                    SettingsRow(
                        title: NSLocalizedString("settings.editor.font_family.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.font_family.subtitle", comment: ""),
                        systemImage: "textformat"
                    ) {
                        Picker("", selection: fontFamilyBinding) {
                            ForEach(fontFamilies, id: \.self) { family in
                                Text(family)
                                    .tag(family)
                            }
                        }
                        .labelsHidden()
                        .frame(width: AppConstants.Settings.pickerNarrowWidth)
                        .accessibilityIdentifier("Settings.FontFamily")
                    }
                    
                    SettingsRow(
                        title: NSLocalizedString("settings.editor.font_size.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.font_size.subtitle", comment: ""),
                        systemImage: "textformat.size"
                    ) {
                        HStack(spacing: 12) {
                            Slider(
                                value: fontSizeBinding,
                                in: AppConstants.Editor.minFontSize...AppConstants.Editor.maxFontSize,
                                step: 1
                            )
                            .frame(width: AppConstants.Settings.sliderWidth)
                            .accessibilityIdentifier("Settings.FontSize")
                            
                            Text("\(Int(ui.fontSize)) \(NSLocalizedString("settings.editor.font_size.unit", comment: ""))")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: NSLocalizedString("settings.editor.indentation.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.indentation.subtitle", comment: ""),
                        systemImage: "arrow.right.to.line"
                    ) {
                        Picker("", selection: indentationStyleBinding) {
                            ForEach(IndentationStyle.allCases, id: \.self) { style in
                                Text(style.displayName)
                                    .tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: AppConstants.Settings.pickerWideWidth)
                        .accessibilityIdentifier("Settings.IndentationStyle")
                    }
                    
                    SettingsRow(
                        title: NSLocalizedString("settings.editor.line_numbers.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.line_numbers.subtitle", comment: ""),
                        systemImage: "list.number"
                    ) {
                        Toggle("", isOn: showLineNumbersBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.ShowLineNumbers")
                    }
                    
                    SettingsRow(
                        title: NSLocalizedString("settings.editor.word_wrap.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.word_wrap.subtitle", comment: ""),
                        systemImage: "arrow.left.and.right.text.vertical"
                    ) {
                        Toggle("", isOn: wordWrapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.WordWrap")
                    }
                    
                    SettingsRow(
                        title: NSLocalizedString("settings.editor.minimap.title", comment: ""),
                        subtitle: NSLocalizedString("settings.editor.minimap.subtitle", comment: ""),
                        systemImage: "rectangle.inset.filled.and.person.filled"
                    ) {
                        Toggle("", isOn: minimapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Minimap")
                    }
                }
                
                SettingsCard(
                    title: NSLocalizedString("settings.workspace.title", comment: ""),
                    subtitle: NSLocalizedString("settings.workspace.subtitle", comment: "")
                ) {
                    SettingsRow(
                        title: NSLocalizedString("settings.workspace.sidebar.title", comment: ""),
                        subtitle: NSLocalizedString("settings.workspace.sidebar.subtitle", comment: ""),
                        systemImage: "sidebar.leading"
                    ) {
                        Toggle("", isOn: sidebarBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Sidebar")
                    }
                }
                
                SettingsCard(
                    title: NSLocalizedString("settings.defaults.title", comment: ""),
                    subtitle: NSLocalizedString("settings.defaults.subtitle", comment: "")
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("settings.defaults.reset.title", comment: ""))
                                .font(.body)
                            Text(NSLocalizedString("settings.defaults.reset.subtitle", comment: ""))
                                .font(.caption)
                            Text(NSLocalizedString("settings.defaults.reset.warning", comment: ""))
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Button(NSLocalizedString("settings.defaults.reset.button", comment: "")) {
                            ui.resetToDefaults()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.2))
                    }
                }
            }
            .padding(.top, AppConstants.Settings.contentTopPadding)
        }
    }
    
    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { ui.selectedTheme },
            set: { ui.setTheme($0) }
        )
    }
    
    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { ui.fontSize },
            set: { ui.updateFontSize($0) }
        )
    }
    
    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { ui.fontFamily },
            set: { ui.updateFontFamily($0) }
        )
    }

    private var indentationStyleBinding: Binding<IndentationStyle> {
        Binding(
            get: { ui.indentationStyle },
            set: { ui.setIndentationStyle($0) }
        )
    }
    
    private var showLineNumbersBinding: Binding<Bool> {
        Binding(
            get: { ui.showLineNumbers },
            set: { ui.setShowLineNumbers($0) }
        )
    }
    
    private var wordWrapBinding: Binding<Bool> {
        Binding(
            get: { ui.wordWrap },
            set: { ui.setWordWrap($0) }
        )
    }
    
    private var minimapBinding: Binding<Bool> {
        Binding(
            get: { ui.minimapVisible },
            set: { ui.setMinimapVisible($0) }
        )
    }
    
    private var sidebarBinding: Binding<Bool> {
        Binding(
            get: { ui.isSidebarVisible },
            set: { ui.setSidebarVisible($0) }
        )
    }
}
