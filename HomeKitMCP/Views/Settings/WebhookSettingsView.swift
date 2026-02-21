import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService

    @State private var webhookURL: String
    @State private var hasEdited = false
    @State private var showingSaveAlert = false

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
                Toggle("Enable Webhook Notifications", isOn: $viewModel.webhookEnabled)

                Group {
                    TextField("https://example.com/webhook", text: $webhookURL)
                        .textFieldStyle(.plain)
                        .foregroundColor(Theme.Tint.secondary)
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
                Label("Configuration", systemImage: "paperplane")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configure which devices trigger webhooks in the Devices tab.")
                    Text("Payloads are signed with HMAC-SHA256 in the X-Signature-256 header.")
                }
            }

            if viewModel.webhookEnabled {
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
                    Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Webhooks")
        .alert("Saved", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Webhook URL has been saved.")
        }
    }
}

#Preview {
    NavigationStack {
        WebhookSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
