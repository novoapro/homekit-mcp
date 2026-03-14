import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var showingResetSettingsConfirmation = false
    @State private var showingClearWorkflowsConfirmation = false
    @State private var showingClearRegistryConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("Temperature Unit", selection: $viewModel.temperatureUnit) {
                    Text("Celsius").tag("celsius")
                    Text("Fahrenheit").tag("fahrenheit")
                }
            } header: {
                Label("Display", systemImage: "thermometer")
            } footer: {
                Text("Temperature values throughout the app, REST API, MCP tools, and WebSocket broadcasts will be displayed and accepted in the selected unit.")
            }

            Section {
                Toggle("Enable Logging", isOn: $viewModel.loggingEnabled)

                if viewModel.loggingEnabled {
                    Toggle("Expose via API", isOn: $viewModel.logAccessEnabled)

                    Picker("Buffer Size", selection: $viewModel.logCacheSize) {
                        Text("100").tag(100)
                        Text("250").tag(250)
                        Text("500").tag(500)
                        Text("1,000").tag(1000)
                        Text("2,000").tag(2000)
                        Text("5,000").tag(5000)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 10) {
                            LogCategoryCard(
                                icon: "waveform.path",
                                title: "Device State Changes",
                                color: Theme.Tint.main,
                                isEnabled: $viewModel.deviceStateLoggingEnabled
                            )
                            LogCategoryCard(
                                icon: "network",
                                title: "REST Calls",
                                color: .indigo,
                                isEnabled: $viewModel.restLoggingEnabled,
                                mode: .detailPicker($viewModel.restDetailedLogsEnabled)
                            )
                            LogCategoryCard(
                                icon: "gearshape.2",
                                title: "Workflows",
                                color: .green,
                                isEnabled: $viewModel.workflowLoggingEnabled,
                                mode: .executedPicker($viewModel.logSkippedWorkflows)
                            )
                        }
                        VStack(spacing: 10) {
                            LogCategoryCard(
                                icon: "server.rack",
                                title: "MCP Calls",
                                color: .teal,
                                isEnabled: $viewModel.mcpLoggingEnabled,
                                mode: .detailPicker($viewModel.mcpDetailedLogsEnabled)
                            )
                            LogCategoryCard(
                                icon: "arrow.up.forward.app",
                                title: "Webhooks",
                                color: Theme.Tint.secondary,
                                isEnabled: $viewModel.webhookLoggingEnabled,
                                mode: .detailPicker($viewModel.webhookDetailedLogsEnabled)
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                    .padding(8)
                }
            } header: {
                Label("Logging", systemImage: "doc.text")
            } footer: {
                Text(viewModel.loggingEnabled
                    ? "Disabled categories are not captured and do not consume buffer space. Detailed captures full request/response payloads. Expose via API makes logs available through the MCP get_logs tool and REST /logs endpoint. Buffer size takes effect on next app launch."
                    : "Logging is disabled. No log entries will be captured.")
            }

            Section {
                Button("Reset Device Settings", role: .destructive) {
                    showingResetSettingsConfirmation = true
                }

                Button("Clear All Workflows", role: .destructive) {
                    showingClearWorkflowsConfirmation = true
                }

                Button("Clear Device Registry", role: .destructive) {
                    showingClearRegistryConfirmation = true
                }
            } header: {
                Label("Data", systemImage: "externaldrive")
            } footer: {
                Text("Reset Device Settings disables all characteristics (enabled and observed off). Clear All Workflows removes every workflow. Clear Device Registry wipes the entire registry and re-imports all devices from HomeKit with new stable IDs.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("General")
        .alert("Reset Device Settings?", isPresented: $showingResetSettingsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.deviceRegistryService.resetAllSettings()
                }
            }
        } message: {
            Text("This will disable all device characteristics — setting both enabled and observed to off.")
        }
        .alert("Clear All Workflows?", isPresented: $showingClearWorkflowsConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await viewModel.workflowStorageService.deleteAllWorkflows()
                }
            }
        } message: {
            Text("This will permanently delete all workflows. This action cannot be undone.")
        }
        .alert("Clear Device Registry?", isPresented: $showingClearRegistryConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear & Re-Import", role: .destructive) {
                Task {
                    await viewModel.deviceRegistryService.clearRegistry()
                    await MainActor.run {
                        viewModel.homeKitManager.resyncAllDevices()
                    }
                }
            }
        } message: {
            Text("This will wipe the entire device registry and re-import all devices from HomeKit with new stable IDs. Any existing workflow references to devices will become orphaned.")
        }
    }
}

// MARK: - Log Category Card

private enum LogCardMode {
    case toggle
    case detailPicker(Binding<Bool>)     // Off / On / Detailed — secondary binding controls detailed
    case executedPicker(Binding<Bool>)   // Off / On / Executed — secondary binding controls logSkipped (inverted)
}

private struct LogCategoryCard: View {
    let icon: String
    let title: String
    let color: Color
    @Binding var isEnabled: Bool
    let mode: LogCardMode

    init(icon: String, title: String, color: Color, isEnabled: Binding<Bool>, mode: LogCardMode = .toggle) {
        self.icon = icon
        self.title = title
        self.color = color
        self._isEnabled = isEnabled
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isEnabled ? color : Theme.Text.tertiary)
                    .frame(width: 20)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(isEnabled ? Theme.Text.primary : Theme.Text.tertiary)
                    .lineLimit(1)

                Spacer()

                if case .toggle = mode {
                    Toggle("", isOn: $isEnabled)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
            }

            switch mode {
            case .toggle:
                EmptyView()
            case .detailPicker(let detailEnabled):
                threeStatePicker(
                    labels: ("Off", "On", "Detailed"),
                    secondary: detailEnabled,
                    invertSecondary: false
                )
            case .executedPicker(let logSkipped):
                threeStatePicker(
                    labels: ("Off", "On", "Executed"),
                    secondary: logSkipped,
                    invertSecondary: true
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.detailBackground)
        .cornerRadius(Theme.CornerRadius.small)
    }

    @ViewBuilder
    private func threeStatePicker(labels: (String, String, String), secondary: Binding<Bool>, invertSecondary: Bool) -> some View {
        let selection = Binding<Int>(
            get: {
                if !isEnabled { return 0 }
                let flag = invertSecondary ? !secondary.wrappedValue : secondary.wrappedValue
                return flag ? 2 : 1
            },
            set: { newValue in
                switch newValue {
                case 0:
                    isEnabled = false
                    secondary.wrappedValue = invertSecondary ? true : false
                case 1:
                    isEnabled = true
                    secondary.wrappedValue = invertSecondary ? true : false
                case 2:
                    isEnabled = true
                    secondary.wrappedValue = invertSecondary ? false : true
                default: break
                }
            }
        )

        Picker("", selection: selection) {
            Text(labels.0).tag(0)
            Text(labels.1).tag(1)
            Text(labels.2).tag(2)
        }
        .pickerStyle(.segmented)
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
