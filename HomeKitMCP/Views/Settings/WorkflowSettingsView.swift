import SwiftUI

struct WorkflowSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable Workflows", isOn: $viewModel.workflowsEnabled)
            } header: {
                Label("Workflows", systemImage: "bolt.fill")
            } footer: {
                Text("When disabled, all workflow tools, REST endpoints, triggers, and scheduled automations are deactivated. Existing workflow definitions are preserved.")
            }

            Section {
                HStack {
                    Text("Latitude")
                    Spacer()
                    TextField("e.g. 37.7749", value: $viewModel.sunEventLatitude, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                HStack {
                    Text("Longitude")
                    Spacer()
                    TextField("e.g. -122.4194", value: $viewModel.sunEventLongitude, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
                if viewModel.hasValidCoordinates {
                    HStack {
                        Label("Sunrise", systemImage: "sunrise.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        if let sunrise = viewModel.todaySunrise {
                            Text(sunrise, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Label("Sunset", systemImage: "sunset.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        if let sunset = viewModel.todaySunset {
                            Text(sunset, format: .dateTime.month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("Location", systemImage: "location")
            } footer: {
                Text("Required for sunrise/sunset workflow triggers. Find your coordinates at latlong.net.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Workflows")
    }
}

#Preview {
    NavigationStack {
        WorkflowSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
