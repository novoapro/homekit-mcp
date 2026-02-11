import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var webhookURL = ""
    @State private var showingSaveAlert = false
    @State private var hasEdited = false

    private var urlIsValid: Bool {
        webhookURL.isEmpty || viewModel.isValidURL(webhookURL)
    }

    private var hasUnsavedChanges: Bool {
        hasEdited && webhookURL != (viewModel.storage.webhookURL ?? "")
    }

    var body: some View {
        Form {
            webhookSection
            webhookStatusSection
            mcpServerSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert("Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Webhook URL has been saved.")
        }
    }

    // MARK: - Sections

    private var webhookSection: some View {
        Section {
            TextField("https://example.com/webhook", text: $webhookURL)
                .textFieldStyle(.roundedBorder)
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
        } header: {
            Text("Webhook Configuration")
        } footer: {
            Text("State changes will be sent as HTTP POST requests with a JSON payload to this URL.")
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
            Toggle("Enable MCP Server", isOn: Binding(
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
            Text("MCP Server")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streamable HTTP: http://127.0.0.1:\(viewModel.storage.mcpServerPort)/mcp")
                Text("Legacy SSE: http://127.0.0.1:\(viewModel.storage.mcpServerPort)/sse")
            }
            .font(.caption)
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
