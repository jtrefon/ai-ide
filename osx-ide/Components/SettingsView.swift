import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Text("General")
                }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("Settings")
                .font(.headline)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
}
