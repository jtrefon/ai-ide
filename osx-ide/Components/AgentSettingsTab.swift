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
                        title: "CLI initial wait",
                        subtitle: "Default first wait window for run_command sessions before control returns (5-120s).",
                        systemImage: "timer"
                    ) {
                        HStack(spacing: 12) {
                            Slider(
                                value: cliTimeoutBinding,
                                in: 5...120,
                                step: 1
                            )
                            .frame(width: AppConstants.Settings.sliderWidth)
                            .accessibilityIdentifier("Settings.Agent.CliTimeoutSeconds")

                            Text("\(Int(ui.cliTimeoutSeconds)) s")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsRow(
                        title: "Memory",
                        subtitle: "Allow the agent to store and retrieve local memories.",
                        systemImage: "brain"
                    ) {
                        Toggle("", isOn: memoryEnabledBinding)
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Agent.MemoryEnabled")
                    }

                    SettingsRow(
                        title: "QA review",
                        subtitle: "Run an advisory QA pass after the agent completes a response.",
                        systemImage: "checkmark.seal"
                    ) {
                        Toggle("", isOn: qaReviewEnabledBinding)
                            .toggleStyle(.switch)
                            .accessibilityIdentifier("Settings.Agent.QAReviewEnabled")
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

    private var memoryEnabledBinding: Binding<Bool> {
        Binding(
            get: { ui.agentMemoryEnabled },
            set: { ui.setAgentMemoryEnabled($0) }
        )
    }

    private var qaReviewEnabledBinding: Binding<Bool> {
        Binding(
            get: { ui.agentQAReviewEnabled },
            set: { ui.setAgentQAReviewEnabled($0) }
        )
    }
}
