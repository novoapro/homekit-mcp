import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Hide Room Name in App", isOn: $viewModel.hideRoomNameInTheApp)
            } header: {
                Label("Display", systemImage: "paintbrush")
            }

            Section {
                Toggle("Device State Change Logs", isOn: $viewModel.deviceStateLoggingEnabled)
                Toggle("Detailed Logs", isOn: $viewModel.detailedLogsEnabled)
            } header: {
                Label("Logging", systemImage: "doc.text")
            } footer: {
                Text("Device state change logs record every HomeKit device update. Detailed logs capture full request and response data for MCP, REST, and webhook entries.")
            }

            Section {
                Toggle("Enable State Polling", isOn: $viewModel.pollingEnabled)

                Picker("Polling Interval", selection: $viewModel.pollingInterval) {
                    Text("10 seconds").tag(10)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("120 seconds").tag(120)
                    Text("300 seconds").tag(300)
                }
                .disabled(!viewModel.pollingEnabled)
                .opacity(viewModel.pollingEnabled ? 1 : 0.5)
            } header: {
                Label("State Polling", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Periodically reads device states from HomeKit to detect missed callbacks. Logs corrections when actual state differs from cached state.")
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
