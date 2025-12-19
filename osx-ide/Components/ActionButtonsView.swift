//
//  ActionButtonsView.swift
//  osx-ide
//
//  Created by AI Assistant on 25/08/2025.
//

import SwiftUI

struct ActionButtonsView: View {
    var onExplain: () -> Void
    var onRefactor: () -> Void
    var onGenerate: () -> Void
    var onFix: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ActionButton(title: "Explain", icon: "questionmark.circle", action: onExplain)
            ActionButton(title: "Refactor", icon: "arrow.triangle.2.circlepath", action: onRefactor)
            ActionButton(title: "Generate", icon: "sparkles", action: onGenerate)
            ActionButton(title: "Fix", icon: "wrench", action: onFix)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(ActionButtonStyle())
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.blue.opacity(configuration.isPressed ? 0.7 : 0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
    }
}

struct ActionButtonsView_Previews: PreviewProvider {
    static var previews: some View {
        ActionButtonsView(
            onExplain: {},
            onRefactor: {},
            onGenerate: {},
            onFix: {}
        )
    }
}