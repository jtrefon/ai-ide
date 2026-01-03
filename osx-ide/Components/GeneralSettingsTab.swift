//
//  GeneralSettingsTab.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var appState: AppState
    
    private let fontFamilies = [
        "SF Mono",
        "Menlo",
        "JetBrains Mono",
        "Fira Code",
        "Source Code Pro",
        "Courier New"
    ]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard(
                    title: "Appearance",
                    subtitle: "Choose a theme that feels native and calm."
                ) {
                    SettingsRow(
                        title: "Theme",
                        subtitle: "Match the system or pick a style.",
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
                        .frame(width: 220)
                        .accessibilityIdentifier("Settings.Theme")
                    }
                }
                
                SettingsCard(
                    title: "Editor",
                    subtitle: "Typography and layout tuned for focus."
                ) {
                    SettingsRow(
                        title: "Font family",
                        subtitle: "Select a monospace font for code.",
                        systemImage: "textformat"
                    ) {
                        Picker("", selection: fontFamilyBinding) {
                            ForEach(fontFamilies, id: \.self) { family in
                                Text(family)
                                    .tag(family)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .accessibilityIdentifier("Settings.FontFamily")
                    }
                    
                    SettingsRow(
                        title: "Font size",
                        subtitle: "Adjust the editor point size.",
                        systemImage: "textformat.size"
                    ) {
                        HStack(spacing: 12) {
                            Slider(
                                value: fontSizeBinding,
                                in: AppConstants.Editor.minFontSize...AppConstants.Editor.maxFontSize,
                                step: 1
                            )
                            .frame(width: 180)
                            .accessibilityIdentifier("Settings.FontSize")
                            
                            Text("\(Int(appState.ui.fontSize)) pt")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: "Indentation",
                        subtitle: "Choose tabs or spaces.",
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
                        .frame(width: 220)
                        .accessibilityIdentifier("Settings.IndentationStyle")
                    }
                    
                    SettingsRow(
                        title: "Line numbers",
                        subtitle: "Show a gutter for navigation.",
                        systemImage: "list.number"
                    ) {
                        Toggle("", isOn: showLineNumbersBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.ShowLineNumbers")
                    }
                    
                    SettingsRow(
                        title: "Word wrap",
                        subtitle: "Keep long lines within the view.",
                        systemImage: "arrow.left.and.right.text.vertical"
                    ) {
                        Toggle("", isOn: wordWrapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.WordWrap")
                    }
                    
                    SettingsRow(
                        title: "Minimap",
                        subtitle: "Quickly scan large files.",
                        systemImage: "rectangle.inset.filled.and.person.filled"
                    ) {
                        Toggle("", isOn: minimapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Minimap")
                    }
                }
                
                SettingsCard(
                    title: "Workspace",
                    subtitle: "Layout options for your daily flow."
                ) {
                    SettingsRow(
                        title: "Sidebar",
                        subtitle: "Show the file tree and tabs.",
                        systemImage: "sidebar.leading"
                    ) {
                        Toggle("", isOn: sidebarBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Sidebar")
                    }
                }
                
                SettingsCard(
                    title: "Defaults",
                    subtitle: "Restore the original configuration."
                ) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reset settings")
                                .font(.body)
                            Text("Revert all preferences to their factory values.")
                                .font(.caption)
                            Text("This will restore layouts and editor preferences.")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        
                        Spacer()
                        
                        Button("Reset to Defaults") {
                            appState.ui.resetToDefaults()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.white.opacity(0.2))
                    }
                }
            }
            .padding(.top, 4)
        }
    }
    
    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { appState.ui.selectedTheme },
            set: { appState.ui.setTheme($0) }
        )
    }
    
    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { appState.ui.fontSize },
            set: { appState.ui.updateFontSize($0) }
        )
    }
    
    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { appState.ui.fontFamily },
            set: { appState.ui.updateFontFamily($0) }
        )
    }

    private var indentationStyleBinding: Binding<IndentationStyle> {
        Binding(
            get: { appState.ui.indentationStyle },
            set: { appState.ui.setIndentationStyle($0) }
        )
    }
    
    private var showLineNumbersBinding: Binding<Bool> {
        Binding(
            get: { appState.ui.showLineNumbers },
            set: { appState.ui.setShowLineNumbers($0) }
        )
    }
    
    private var wordWrapBinding: Binding<Bool> {
        Binding(
            get: { appState.ui.wordWrap },
            set: { appState.ui.setWordWrap($0) }
        )
    }
    
    private var minimapBinding: Binding<Bool> {
        Binding(
            get: { appState.ui.minimapVisible },
            set: { appState.ui.setMinimapVisible($0) }
        )
    }
    
    private var sidebarBinding: Binding<Bool> {
        Binding(
            get: { appState.ui.isSidebarVisible },
            set: { appState.ui.setSidebarVisible($0) }
        )
    }
}
