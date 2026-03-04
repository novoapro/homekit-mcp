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
                Toggle("Log Device State Changes", isOn: $viewModel.deviceStateLoggingEnabled)
                Toggle("Log Detailed Info", isOn: $viewModel.detailedLogsEnabled)
                Toggle("Log Access via API", isOn: $viewModel.logAccessEnabled)
                Toggle("Log Skipped Workflows", isOn: $viewModel.logSkippedWorkflows)

                Picker("Log Buffer Size", selection: $viewModel.logCacheSize) {
                    Text("100").tag(100)
                    Text("250").tag(250)
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("2,000").tag(2000)
                    Text("5,000").tag(5000)
                }
            } header: {
                Label("Logging", systemImage: "doc.text")
            } footer: {
                Text("When enabled, state changes for observed characteristics are recorded to the log buffer. Detailed logs capture full request and response data for MCP, REST, and webhook entries. Log Access via API exposes logs through the MCP get_logs tool and the REST /logs endpoint. Log Skipped Workflows controls whether workflows whose guard conditions were not met appear in the log. Log buffer size controls the maximum number of log entries kept in memory and on disk — takes effect on next app launch.")
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

#Preview {
    NavigationStack {
        GeneralSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
