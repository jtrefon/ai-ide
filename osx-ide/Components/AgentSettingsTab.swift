import SwiftUI

struct AgentSettingsTab: View {
    @ObservedObject var ui: UIStateManager

    var body: some View {
        ScrollView {
            VStack(spacing: AppConstants.Settings.sectionSpacing) {
                SettingsCard(
                    title: "Agent",
                    subtitle: "Controls for how the agent executes tools and commands."
                ) {
                    SettingsRow(
                        title: "CLI timeout",
                        subtitle: "Terminate run_command after this many seconds (1–300).",
                        systemImage: "timer"
                    ) {
                        HStack(spacing: 12) {
                            Slider(
                                value: cliTimeoutBinding,
                                in: 1...300,
                                step: 1
                            )
                            .frame(width: AppConstants.Settings.sliderWidth)
                            .accessibilityIdentifier("Settings.Agent.CliTimeoutSeconds")

                            Text("\(Int(ui.cliTimeoutSeconds)) s")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, AppConstants.Settings.contentTopPadding)
        }
    }

    private var cliTimeoutBinding: Binding<Double> {
        Binding(
            get: { ui.cliTimeoutSeconds },
            set: { ui.setCliTimeoutSeconds($0) }
        )
    }
}
