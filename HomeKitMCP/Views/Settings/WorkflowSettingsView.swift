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
                    TextField("Zip / Postal Code", text: $viewModel.sunEventZipCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                        .onSubmit {
                            viewModel.geocodeZipCode()
                        }

                    Spacer()

                    if viewModel.isGeocoding {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Lookup") {
                            viewModel.geocodeZipCode()
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.sunEventZipCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if let error = viewModel.geocodingError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                if viewModel.hasValidCoordinates {
                    HStack {
                        Label(viewModel.sunEventCityName.isEmpty ? "Location set" : viewModel.sunEventCityName,
                              systemImage: "mappin.and.ellipse")
                        Spacer()

                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "sunrise.fill")
                                    .foregroundStyle(.orange)
                                if let sunrise = viewModel.todaySunrise {
                                    Text(sunrise, format: .dateTime.hour().minute())
                                } else {
                                    Text("—")
                                }
                            }

                            HStack(spacing: 4) {
                                Image(systemName: "sunset.fill")
                                    .foregroundStyle(.orange)
                                if let sunset = viewModel.todaySunset {
                                    Text(sunset, format: .dateTime.hour().minute())
                                } else {
                                    Text("—")
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    }
                }
            } header: {
                Label("Location", systemImage: "location")
            } footer: {
                Text("Enter your zip or postal code to enable sunrise/sunset workflow triggers.")
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
