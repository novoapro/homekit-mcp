import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    // Observe storage directly so @Published changes (e.g. mcpServerBindAddress) trigger re-renders
    @ObservedObject private var storage: StorageService
    @State private var webhookURL: String
    @State private var showingSaveAlert = false
    @State private var hasEdited = false
    @State private var showingResetConfirmation = false
    @State private var aiApiKeyInput = ""
    @State private var showingAIApiKey = false
    @State private var showingApiToken = false
    @State private var showingRegenerateConfirmation = false
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.storage = viewModel.storage
        self._webhookURL = State(initialValue: viewModel.storage.webhookURL ?? "")
    }

    private var urlIsValid: Bool {
        webhookURL.isEmpty || viewModel.isValidURL(webhookURL)
    }

    private var hasUnsavedChanges: Bool {
        hasEdited && webhookURL != (viewModel.storage.webhookURL ?? "")
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hide Room Name in App", isOn: $viewModel.hideRoomNameInTheApp)
            } header: {
                Label("UI", systemImage: "paintbrush")
            }
            loggingSection
                .listRowBackground(Theme.contentBackground)
            aiAssistantSection
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
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Copied to clipboard")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 24)
                .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCopiedToast)
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

    // MARK: - Toast

    private func showCopyToast() {
        copiedToastTask?.cancel()
        showCopiedToast = true
        copiedToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { showCopiedToast = false }
        }
    }

    // MARK: - Sections

    private var loggingSection: some View {
        Section {
            Toggle("Detailed Logs", isOn: $viewModel.detailedLogsEnabled)
        } header: {
            Label("Logging", systemImage: "doc.text")
        } footer: {
            Text("When enabled, full request and response data is captured for MCP, REST, and webhook logs. Tap a log entry to expand details.")
        }
    }

    // MARK: - AI Assistant Section

    private var aiAssistantSection: some View {
        Section {
            Toggle("Enable AI Workflow Builder", isOn: $viewModel.aiEnabled)

            Group {
                Picker("Provider", selection: $viewModel.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                // API Key
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.aiApiKeyConfigured {
                        // Key is set — show masked placeholder and clear option only
                        HStack {
                            Text(String(repeating: "\u{2022}", count: 32))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        .allowsHitTesting(false)
                        Button("Clear Key", role: .destructive) {
                            viewModel.clearAIApiKey()
                            aiApiKeyInput = ""
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    } else {
                        // No key set — show input field and save button
                        SecureField("API Key", text: $aiApiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        Button("Save Key") {
                            viewModel.saveAIApiKey(aiApiKeyInput)
                            aiApiKeyInput = ""
                        }
                        .buttonStyle(.borderless)
                        .disabled(aiApiKeyInput.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { /* absorb row tap so it doesn't fire buttons */ }

                // Model Override
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Model ID (optional)", text: $viewModel.aiModelId)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("Default: \(viewModel.aiProvider.defaultModel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Test Connection
                HStack {
                    Button {
                        viewModel.testAIConnection()
                    } label: {
                        HStack {
                            if viewModel.isTestingAI {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(!viewModel.aiApiKeyConfigured || viewModel.isTestingAI)

                    Spacer()

                    if let result = viewModel.aiTestResult {
                        switch result {
                        case .success:
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        case .failure(let error):
                            Label(error, systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .disabled(!viewModel.aiEnabled)
            .opacity(viewModel.aiEnabled ? 1 : 0.5)
        } header: {
            Label("AI Assistant", systemImage: "sparkles")
        } footer: {
            Text("Configure an LLM provider to create workflows from natural language descriptions.")
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
            Label("Webhook Configuration", systemImage: "paperplane")
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Configure which devices trigger webhooks in the Devices tab.")
                Text("Payloads are signed with HMAC-SHA256 in the X-Signature-256 header.")
            }
        }
    }

    private var webhookStatusSection: some View {
        Section {
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
        } header: {
            Label("Webhook Status", systemImage: "antenna.radiowaves.left.and.right")
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

            Picker("Binding Interface", selection: Binding(
                get: { viewModel.storage.mcpServerBindAddress },
                set: { viewModel.storage.mcpServerBindAddress = $0 }
            )) {
                Text("127.0.0.1 (Localhost only)").tag("127.0.0.1")
                Text("0.0.0.0 (All interfaces)").tag("0.0.0.0")
            }
            .disabled(viewModel.mcpServerRunning)

            // API Token
            VStack(alignment: .leading, spacing: 6) {
                Text("API Token")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    if showingApiToken {
                        Text(viewModel.mcpApiToken)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(String(repeating: "\u{2022}", count: 32))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        showingApiToken.toggle()
                    } label: {
                        Image(systemName: showingApiToken ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        #if targetEnvironment(macCatalyst)
                        UIPasteboard.general.string = viewModel.mcpApiToken
                        #endif
                        showCopyToast()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    Button("Regenerate", role: .destructive) {
                        showingRegenerateConfirmation = true
                    }
                    .font(.subheadline)
                }
            }
            .alert("Regenerate API Token?", isPresented: $showingRegenerateConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Regenerate", role: .destructive) {
                    viewModel.regenerateMCPApiToken()
                    showingApiToken = true
                }
            } message: {
                Text("All existing MCP clients will need to be updated with the new token. The server must be restarted for the new token to take effect.")
            }
            // Endpoint URLs
            if viewModel.mcpServerRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoints")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.Text.secondary)

                    let displayHost = viewModel.storage.mcpServerBindAddress == "0.0.0.0"
                        ? viewModel.localIPAddress
                        : viewModel.storage.mcpServerBindAddress
                    endpointRow(label: "MCP Streamable", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/mcp")
                    endpointRow(label: "MCP Legacy SSE", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/sse")
                    endpointRow(label: "REST API", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/devices")
                }
            }
        } header: {
            Label("External Services (MCP & REST)", systemImage: "server.rack")
        } footer: {
            Text("All endpoints require an Authorization: Bearer <token> header.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var dataSection: some View {
        Section {
            Button("Reset Device Configuration", role: .destructive) {
                showingResetConfirmation = true
            }
        } header: {
            Label("Data", systemImage: "externaldrive")
        } footer: {
            Text("Resets all per-device MCP visibility and webhook notification toggles to defaults.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Build", value: "1")
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }

    // MARK: - Helpers

    private func endpointRow(label: String, url: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(Theme.Text.tertiary)
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.Text.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                #if targetEnvironment(macCatalyst)
                UIPasteboard.general.string = url
                #endif
                showCopyToast()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(Theme.Tint.main)
            }
            .buttonStyle(.plain)
            .help("Copy URL")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
