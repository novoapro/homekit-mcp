import SwiftUI

struct WebhookSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService

    @State private var newAllowlistEntry = ""

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.storage = viewModel.storage
    }

    var body: some View {
        Form {
            Section {
                Label("App-wide setting — applies to all webhook calls, including device state notifications and automation actions.", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.webhookPrivateIPAllowlist, id: \.self) { entry in
                    HStack {
                        Text(entry)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.webhookPrivateIPAllowlist.removeAll { $0 == entry }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("192.168.1.* or *.local", text: $newAllowlistEntry)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    Button("Add") {
                        let trimmed = newAllowlistEntry.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty,
                              !viewModel.webhookPrivateIPAllowlist.contains(trimmed) else { return }
                        viewModel.webhookPrivateIPAllowlist.append(trimmed)
                        newAllowlistEntry = ""
                    }
                    .buttonStyle(.borderless)
                    .disabled(newAllowlistEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Label("Private Network Allow List", systemImage: "network.badge.shield.half.filled")
            } footer: {
                Text("By default, webhooks to private IP ranges (192.168.x.x, 10.x.x.x, etc.) are blocked. Add a host or pattern to allow it. Use * as a wildcard (e.g. 192.168.1.* or *.local).")
            }

            Section {
                if viewModel.webhookEndpoints.isEmpty {
                    Text("No webhook endpoints configured.")
                        .foregroundStyle(.secondary)
                }

                ForEach($viewModel.webhookEndpoints) { $endpoint in
                    WebhookEndpointRow(
                        endpoint: $endpoint,
                        status: viewModel.endpointStatuses[endpoint.id] ?? .idle,
                        isTesting: viewModel.testingEndpointId == endpoint.id,
                        isValidURL: viewModel.isValidURL,
                        onTest: { viewModel.sendTestWebhook(endpointId: endpoint.id) },
                        onDelete: {
                            viewModel.webhookEndpoints.removeAll { $0.id == endpoint.id }
                        },
                        deviceRegistryService: viewModel.deviceRegistryService
                    )
                }
            } header: {
                HStack {
                    Label("Endpoints", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Button {
                        viewModel.webhookEndpoints.append(WebhookEndpoint())
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            } footer: {
                Text("Posts a signed payload to each enabled endpoint whenever an observed device state changes. Each endpoint has its own HMAC-SHA256 signing secret in the X-Signature-256 header. Configure which devices are observed in the Devices tab.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Webhooks")
    }
}

// MARK: - Endpoint Row

private struct WebhookEndpointRow: View {
    @Binding var endpoint: WebhookEndpoint
    let status: WebhookStatus
    let isTesting: Bool
    let isValidURL: (String) -> Bool
    let onTest: () -> Void
    let onDelete: () -> Void
    let deviceRegistryService: DeviceRegistryService

    @State private var isExpanded = false
    @State private var showDeviceFilter = false
    @State private var observedDevices: [(id: String, name: String, roomName: String?)] = []

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            endpointContent
        } label: {
            endpointLabel
        }
        .task { await loadObservedDevices() }
    }

    @ViewBuilder
    private var endpointLabel: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(endpoint.enabled ? .green : .gray)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.name.isEmpty ? "Unnamed Endpoint" : endpoint.name)
                    .font(.body)
                if !endpoint.url.isEmpty {
                    Text(endpoint.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var endpointContent: some View {
        Toggle("Enabled", isOn: $endpoint.enabled)

        TextField("Name", text: $endpoint.name)
            .textFieldStyle(.roundedBorder)

        TextField("https://example.com/webhook", text: $endpoint.url)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.URL)
            .autocapitalization(.none)
            .disableAutocorrection(true)

        if !endpoint.url.isEmpty && !isValidURL(endpoint.url) {
            Label("Enter a valid HTTP or HTTPS URL", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundColor(.orange)
        }

        // Device filter
        deviceFilterSection

        // Status & actions
        statusRow

        HStack {
            Button {
                onTest()
            } label: {
                HStack {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                    Text("Send Test")
                }
            }
            .disabled(endpoint.url.isEmpty || !isValidURL(endpoint.url) || isTesting)

            Spacer()

            Button("Remove", role: .destructive) {
                onDelete()
            }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var deviceFilterSection: some View {
        DisclosureGroup("Device Filter") {
            if observedDevices.isEmpty {
                Text("No observed devices. Enable observation in the Devices tab first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(endpoint.deviceFilter.isEmpty ? "All observed devices" : "\(endpoint.deviceFilter.count) device(s) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !endpoint.deviceFilter.isEmpty {
                    Button("Clear filter (listen to all)") {
                        endpoint.deviceFilter = []
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }

                ForEach(observedDevices, id: \.id) { device in
                    let isSelected = endpoint.deviceFilter.contains(device.id)
                    Button {
                        if isSelected {
                            endpoint.deviceFilter.remove(device.id)
                        } else {
                            endpoint.deviceFilter.insert(device.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .blue : .secondary)
                            VStack(alignment: .leading) {
                                Text(device.name)
                                if let room = device.roomName {
                                    Text(room)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            switch status {
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
        .font(.caption)
    }

    private func loadObservedDevices() async {
        let devices = await deviceRegistryService.getObservedDevices()
        await MainActor.run { observedDevices = devices }
    }
}

#Preview {
    NavigationStack {
        WebhookSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
