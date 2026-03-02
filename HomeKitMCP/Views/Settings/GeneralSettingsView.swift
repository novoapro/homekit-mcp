import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Log Device State Changes", isOn: $viewModel.deviceStateLoggingEnabled)
                if viewModel.deviceStateLoggingEnabled {
                    Toggle("Log Only Webhook-Enabled Devices", isOn: $viewModel.logOnlyWebhookDevices)
                }
                Toggle("Log Detailed Info", isOn: $viewModel.detailedLogsEnabled)
                Toggle("Log Access via API", isOn: $viewModel.logAccessEnabled)

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
                Text("Device state change logs record every HomeKit device update. When \"Log Only Webhook-Enabled Devices\" is on, only state changes for characteristics with webhooks enabled are logged. Detailed logs capture full request and response data for MCP, REST, and webhook entries. Log Access via API exposes logs through the MCP get_logs tool and the REST /logs endpoint. Log buffer size controls the maximum number of log entries kept in memory and on disk — takes effect on next app launch.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("General")
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
