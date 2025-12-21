import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @StateObject private var openRouterViewModel = OpenRouterSettingsViewModel()
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.2),
                    Color(red: 0.08, green: 0.1, blue: 0.14),
                    Color(red: 0.06, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .blur(radius: 40)
                .offset(x: 180, y: -220)
                .allowsHitTesting(false)
            
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.blue.opacity(0.08))
                .blur(radius: 60)
                .offset(x: -200, y: 240)
                .allowsHitTesting(false)
            
            VStack(spacing: 16) {
                header
                
                TabView {
                    GeneralSettingsTab(appState: appState)
                        .tabItem {
                            Label("General", systemImage: "gearshape")
                        }
                    
                    AISettingsTab(viewModel: openRouterViewModel)
                        .tabItem {
                            Label("AI", systemImage: "sparkles")
                        }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 560, idealHeight: 620)
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                
                Text("Liquid glass controls for your workspace and editor.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .nativeGlassBackground(.toolbar, cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
        )
    }
    
}

private struct GeneralSettingsTab: View {
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
                            
                            Text("\(Int(appState.fontSize)) pt")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    SettingsRow(
                        title: "Line numbers",
                        subtitle: "Show a gutter for navigation.",
                        systemImage: "list.number"
                    ) {
                        Toggle("", isOn: showLineNumbersBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    
                    SettingsRow(
                        title: "Word wrap",
                        subtitle: "Keep long lines within the view.",
                        systemImage: "arrow.left.and.right.text.vertical"
                    ) {
                        Toggle("", isOn: wordWrapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    
                    SettingsRow(
                        title: "Minimap",
                        subtitle: "Quickly scan large files.",
                        systemImage: "rectangle.inset.filled.and.person.filled"
                    ) {
                        Toggle("", isOn: minimapBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
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
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Reset to Defaults") {
                            appState.resetSettings()
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
            get: { appState.selectedTheme },
            set: { appState.selectedTheme = $0 }
        )
    }
    
    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { appState.fontSize },
            set: { appState.fontSize = $0 }
        )
    }
    
    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { appState.fontFamily },
            set: { appState.fontFamily = $0 }
        )
    }
    
    private var showLineNumbersBinding: Binding<Bool> {
        Binding(
            get: { appState.showLineNumbers },
            set: { appState.showLineNumbers = $0 }
        )
    }
    
    private var wordWrapBinding: Binding<Bool> {
        Binding(
            get: { appState.wordWrap },
            set: { appState.wordWrap = $0 }
        )
    }
    
    private var minimapBinding: Binding<Bool> {
        Binding(
            get: { appState.minimapVisible },
            set: { appState.minimapVisible = $0 }
        )
    }
    
    private var sidebarBinding: Binding<Bool> {
        Binding(
            get: { appState.isSidebarVisible },
            set: { appState.isSidebarVisible = $0 }
        )
    }
}

private struct AISettingsTab: View {
    @ObservedObject var viewModel: OpenRouterSettingsViewModel
    @State private var showAdvanced = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard(
                    title: "OpenRouter Connection",
                    subtitle: "Store your API key and connection details."
                ) {
                    SettingsRow(
                        title: "API key",
                        subtitle: "Stored locally for this device.",
                        systemImage: "key.fill"
                    ) {
                        HStack(spacing: 8) {
                            SecureField("sk-or-...", text: $viewModel.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                            
                            Button("Validate") {
                                Task { await viewModel.validateKey() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        SettingsStatusPill(status: viewModel.keyStatus)
                        Spacer()
                        Button(showAdvanced ? "Hide Advanced" : "Show Advanced") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdvanced.toggle()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if showAdvanced {
                        SettingsRow(
                            title: "Base URL",
                            subtitle: "Defaults to the OpenRouter API endpoint.",
                            systemImage: "link"
                        ) {
                            TextField("https://openrouter.ai/api/v1", text: $viewModel.baseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                        }
                    }
                }
                
                SettingsCard(
                    title: "Model Selection",
                    subtitle: "Search OpenRouter models with autocomplete."
                ) {
                    SettingsRow(
                        title: "Model",
                        subtitle: "Type to search and select.",
                        systemImage: "magnifyingglass"
                    ) {
                        HStack(spacing: 8) {
                            TextField("e.g. openai/gpt-4o-mini", text: $viewModel.modelQuery)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .onSubmit {
                                    viewModel.commitModelEntry()
                                    Task { await viewModel.validateModel() }
                                }
                                .onChange(of: viewModel.modelQuery) { _ in
                                    Task { await viewModel.loadModels() }
                                }
                            
                            Button("Test Latency") {
                                Task { await viewModel.testModel() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    if viewModel.shouldShowSuggestions() {
                        ModelSuggestionList(models: viewModel.filteredModels) { model in
                            viewModel.selectModel(model)
                            Task { await viewModel.validateModel() }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        SettingsStatusPill(status: viewModel.modelStatus)
                        SettingsStatusPill(status: viewModel.modelValidationStatus)
                        SettingsStatusPill(status: viewModel.testStatus)
                        
                        Spacer()
                    }
                }
                
                SettingsCard(
                    title: "System Prompt",
                    subtitle: "Override the default system instructions."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Use this to steer tone, formatting, and coding style.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $viewModel.systemPrompt)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                            )
                        
                        HStack(spacing: 12) {
                            Button("Reset Prompt") {
                                viewModel.systemPrompt = ""
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(.top, 4)
            .onAppear {
                Task { await viewModel.loadModels() }
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
                .opacity(0.4)
            
            content
        }
        .padding(16)
        .nativeGlassBackground(.panel, cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let control: Control
    
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.control = control()
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            control
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsStatusPill: View {
    let status: OpenRouterSettingsViewModel.Status
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            
            Text(status.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
        )
    }
    
    private var statusColor: Color {
        switch status.kind {
        case .idle:
            return Color.gray.opacity(0.6)
        case .loading:
            return Color.blue.opacity(0.8)
        case .success:
            return Color.green.opacity(0.8)
        case .warning:
            return Color.orange.opacity(0.9)
        case .error:
            return Color.red.opacity(0.9)
        }
    }
}

private struct ModelSuggestionList: View {
    let models: [OpenRouterModel]
    let onSelect: (OpenRouterModel) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Matches \(models.count) models")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(models) { model in
                        Button {
                            onSelect(model)
                        } label: {
                            HStack {
                                Text(model.displayName)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .nativeGlassBackground(.popover, cornerRadius: 12)
    }
}

#Preview {
    SettingsView(appState: DependencyContainer.shared.makeAppState())
}
