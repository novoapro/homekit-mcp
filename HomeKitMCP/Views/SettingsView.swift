import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var webhookURL = ""
    @State private var showingSaveAlert = false
    @State private var hasEdited = false
    @State private var showingResetConfirmation = false

    private var urlIsValid: Bool {
        webhookURL.isEmpty || viewModel.isValidURL(webhookURL)
    }

    private var hasUnsavedChanges: Bool {
        hasEdited && webhookURL != (viewModel.storage.webhookURL ?? "")
    }

    var body: some View {
        Form {
            Section("UI") {
                Toggle("Hide Room Name in App", isOn: $viewModel.hideRoomNameInTheApp)
            }
            loggingSection
                .listRowBackground(Theme.contentBackground)
            webhookSection
                .listRowBackground(Theme.contentBackground)
            if viewModel.webhookEnabled {
                webhookStatusSection
                    .listRowBackground(Theme.contentBackground)
            }
            mcpServerSection
                .listRowBackground(Theme.contentBackground)
            dataSection
                .listRowBackground(Theme.contentBackground)
            aboutSection
                .listRowBackground(Theme.contentBackground)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Settings")
        .alert("Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Webhook URL has been saved.")
        }
        .alert("Reset Device Configuration?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                viewModel.resetDeviceConfiguration()
            }
        } message: {
            Text("This will reset all MCP and webhook toggles to their defaults (MCP: on, Webhook: off).")
        }
    }

    // MARK: - Sections

    private var loggingSection: some View {
        Section {
            Toggle("Detailed Logs", isOn: $viewModel.detailedLogsEnabled)
        } header: {
            Text("Logging")
        } footer: {
            Text("When enabled, full request and response data is captured for MCP, REST, and webhook logs. Tap a log entry to expand details.")
        }
    }

    private var webhookSection: some View {
        Section {
            Toggle("Enable Webhook Notifications", isOn: $viewModel.webhookEnabled)

            Group {
                TextField("https://example.com/webhook", text: $webhookURL)
                    .textFieldStyle(.plain)
                    .foregroundColor(Theme.Tint.secondary) // Typed text color
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onAppear {
                        webhookURL = viewModel.storage.webhookURL ?? ""
                    }
                    .onChange(of: webhookURL) { _ in
                        hasEdited = true
                    }

                if hasEdited && !webhookURL.isEmpty && !urlIsValid {
                    Label("Enter a valid HTTP or HTTPS URL", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                HStack {
                    Button("Save") {
                        viewModel.storage.webhookURL = webhookURL.isEmpty ? nil : webhookURL
                        hasEdited = false
                        showingSaveAlert = true
                    }
                    .disabled(!hasUnsavedChanges || (!webhookURL.isEmpty && !urlIsValid))

                    if !webhookURL.isEmpty && viewModel.storage.isWebhookConfigured() {
                        Spacer()
                        Button("Clear") {
                            webhookURL = ""
                            viewModel.storage.webhookURL = nil
                            hasEdited = false
                        }
                        .foregroundColor(.red)
                    }
                }

                if viewModel.storage.isWebhookConfigured() {
                    Label("Webhook configured", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .disabled(!viewModel.webhookEnabled)
            .opacity(viewModel.webhookEnabled ? 1 : 0.5)
        } header: {
            Text("Webhook Configuration")
        } footer: {
            Text("Configure which devices trigger webhooks in the Devices tab.")
        }
    }

    private var webhookStatusSection: some View {
        Section("Webhook Status") {
            HStack {
                switch viewModel.webhookStatus {
                case .idle:
                    Label("No activity yet", systemImage: "circle")
                        .foregroundColor(.secondary)
                case .sending:
                    Label("Sending...", systemImage: "arrow.up.circle")
                        .foregroundColor(.blue)
                case .lastSuccess(let date):
                    Label("Last delivery: \(date, style: .relative) ago", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .lastFailure(_, let error):
                    Label("Failed: \(error)", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(.subheadline)

            Button {
                viewModel.sendTestWebhook()
            } label: {
                HStack {
                    if viewModel.isSendingTest {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Send Test Webhook")
                }
            }
            .disabled(!viewModel.storage.isWebhookConfigured() || viewModel.isSendingTest)
        }
    }

    private var mcpServerSection: some View {
        Section {
            Toggle("Enable External Access", isOn: Binding(
                get: { viewModel.storage.mcpServerEnabled },
                set: { viewModel.toggleMCPServer(enabled: $0) }
            ))

            HStack {
                Text("Status")
                Spacer()
                if viewModel.mcpServerRunning {
                    Label("Running", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else {
                    Label("Stopped", systemImage: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }

            if viewModel.mcpServerRunning {
                LabeledContent("Connected Clients", value: "\(viewModel.mcpConnectedClients)")
            }

            if let error = viewModel.mcpServerError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
            }

            HStack {
                Text("Port")
                Spacer()
                TextField("Port", text: Binding(
                    get: { String(viewModel.storage.mcpServerPort) },
                    set: { if let port = Int($0) { viewModel.storage.mcpServerPort = port } }
                ))
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .disabled(viewModel.mcpServerRunning)
            }
        } header: {
            Text("External Services (MCP & REST)")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "MCP Streamable: http://\(viewModel.localIPAddress):\(viewModel.storage.mcpServerPort)/mcp")
                Text(verbatim: "MCP Legacy SSE: http://\(viewModel.localIPAddress):\(viewModel.storage.mcpServerPort)/sse")
                Text(verbatim: "REST API: http://\(viewModel.localIPAddress):\(viewModel.storage.mcpServerPort)/devices")
            }
            .font(.caption)
        }
    }

    private var dataSection: some View {
        Section {
            Button("Reset Device Configuration", role: .destructive) {
                showingResetConfirmation = true
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Resets all per-device MCP visibility and webhook notification toggles to defaults.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Build", value: "1")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
