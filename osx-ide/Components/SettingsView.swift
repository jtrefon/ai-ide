//
//  SettingsView.swift
//  osx-ide
//
//  Created by AI Assistant on 20/12/2025.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var ui: UIStateManager
    @StateObject private var openRouterViewModel = OpenRouterSettingsViewModel()
    
    var body: some View {
        ZStack {
            // Native Glass Background Effects
            SettingsBackgroundView()
            
            VStack(spacing: 16) {
                TabView {
                    GeneralSettingsTab(ui: ui)
                        .tabItem {
                            Label("General", systemImage: "gearshape")
                        }
                    
                    AISettingsTab(viewModel: openRouterViewModel)
                        .tabItem {
                            Label("AI", systemImage: "sparkles")
                        }

                    AgentSettingsTab(ui: ui)
                        .tabItem {
                            Label("Agent", systemImage: "bolt.fill")
                        }
                    
                    LanguageModulesTab()
                        .tabItem {
                            Label("Modules", systemImage: "puzzlepiece")
                        }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 560, idealHeight: 620)
    }
}

private struct SettingsBackgroundView: View {
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
        }
    }
}

#Preview {
    SettingsView(ui: DependencyContainer().makeAppState().ui)
}
