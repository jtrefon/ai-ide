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
        .padding(AppConstants.Settings.cardPadding)
        .nativeGlassBackground(.panel, cornerRadius: AppConstants.Settings.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppConstants.Settings.cardCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }
}
