//
//  UIRegistry.swift
//  osx-ide
//
//  Created by Jack Trefon on 21/12/2025.
//

import SwiftUI
import Combine

/// A type-erased view provider to allow heterogeneous collections.
public struct PluginView: Identifiable {
    public let id = UUID()
    public let content: AnyView
    public let name: String
    public let iconName: String?
    
    public init<V: View>(name: String, iconName: String? = nil, view: V) {
        self.name = name
        self.iconName = iconName
        self.content = AnyView(view)
    }
}

/// The centralized registry for UI components.
/// Plugins register their views here, and the ContentView renders them dynamically.
@MainActor
public final class UIRegistry: ObservableObject {
    public static let shared = UIRegistry()
    
    @Published private var extensions: [ExtensionPoint: [PluginView]] = [:]
    
    public init() {}
    
    /// Registers a view for a specific extension point.
    /// - Parameters:
    ///   - point: The location to inject the view.
    ///   - name: A display name for the extension (e.g. for tabs).
    ///   - icon: An optional system image name.
    ///   - view: The SwiftUI view to render.
    public func register<V: View>(point: ExtensionPoint, name: String, icon: String? = nil, view: V) {
        if extensions[point] == nil {
            extensions[point] = []
        }
        let pluginView = PluginView(name: name, iconName: icon, view: view)
        extensions[point]?.append(pluginView)
        // Force publish change
        objectWillChange.send()
        
        print("[UIRegistry] Registered '\(name)' at \(point.rawValue)")
    }
    
    /// Retrieves all registered views for an extension point.
    public func views(for point: ExtensionPoint) -> [PluginView] {
        return extensions[point] ?? []
    }
}
