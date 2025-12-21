//
//  SettingsComponents.swift
//  osx-ide
//
//  Created by AI Assistant on 21/12/2025.
//

import SwiftUI

struct SettingsCard<Content: View>: View {
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

struct SettingsRow<Control: View>: View {
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

struct SettingsStatusPill: View {
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

struct ModelSuggestionList: View {
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
