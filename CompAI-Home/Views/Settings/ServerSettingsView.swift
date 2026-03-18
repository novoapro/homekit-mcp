import SwiftUI

struct ServerSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService

    @State private var availableInterfaces: [NetworkInterface] = []
    @State private var newOrigin = ""
    @State private var revealedTokenIds: Set<UUID> = []
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?
    @State private var showingAddToken = false
    @State private var newTokenName = ""
    @State private var tokenToDelete: APIToken?

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.storage = viewModel.storage
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable External Access", isOn: Binding(
                    get: { viewModel.storage.mcpServerEnabled },
                    set: { viewModel.toggleMCPServer(enabled: $0) }
                ))

                HStack {
                    Text("Status")
                    Spacer()
                    if let running = viewModel.mcpServerRunning {
                        if running {
                            Label("Running", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        } else {
                            Label("Stopped", systemImage: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if viewModel.mcpServerRunning == true {
                    LabeledContent("Connected Clients", value: "\(viewModel.mcpConnectedClients)")
                }

                if let error = viewModel.mcpServerError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            } header: {
                Label("Server", systemImage: "power")
            }

            Section {
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
                    .disabled(viewModel.mcpServerRunning == true)
                }

                Picker("Binding Interface", selection: Binding(
                    get: { viewModel.storage.mcpServerBindAddress },
                    set: { viewModel.storage.mcpServerBindAddress = $0 }
                )) {
                    Text("127.0.0.1 (Localhost only)").tag("127.0.0.1")
                    Text("0.0.0.0 (All interfaces)").tag("0.0.0.0")

                    if !availableInterfaces.isEmpty {
                        Divider()
                        ForEach(availableInterfaces) { iface in
                            Text(iface.displayLabel).tag(iface.address)
                        }
                    }
                }
                .disabled(viewModel.mcpServerRunning == true)
                .onAppear {
                    availableInterfaces = NetworkInterfaceEnumerator.availableInterfaces()
                }

                if !NetworkInterfaceEnumerator.isAddressAvailable(viewModel.storage.mcpServerBindAddress) {
                    Label("The selected address is no longer available. The server will fall back to localhost.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
            } header: {
                Label("Network", systemImage: "network")
            }

            // MARK: - CORS
            Section {
                Toggle("Allow Cross-Origin Requests", isOn: Binding(
                    get: { storage.corsEnabled },
                    set: { storage.corsEnabled = $0 }
                ))
                .disabled(viewModel.mcpServerRunning == true)

                if storage.corsEnabled {
                    ForEach(storage.corsAllowedOrigins, id: \.self) { origin in
                        HStack {
                            Text(origin)
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Button {
                                storage.corsAllowedOrigins.removeAll { $0 == origin }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("e.g. http://localhost:5173", text: $newOrigin)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.footnote, design: .monospaced))
                            .autocorrectionDisabled()
                        #if targetEnvironment(macCatalyst)
                            .textInputAutocapitalization(.never)
                        #endif

                        Button {
                            let trimmed = newOrigin.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, !storage.corsAllowedOrigins.contains(trimmed) else { return }
                            storage.corsAllowedOrigins.append(trimmed)
                            newOrigin = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Theme.Tint.main)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Label("CORS", systemImage: "globe")
            } footer: {
                if storage.corsEnabled {
                    Text("When the list is empty, all origins are allowed. Add specific origins to restrict access. Restart the server after changes.")
                } else {
                    Text("When disabled, browsers will block cross-origin requests. Restart the server after changes.")
                }
            }

            // MARK: - API Tokens (Multi-Client)
            Section {
                ForEach(viewModel.apiTokens) { apiToken in
                    tokenRow(apiToken)
                }

                Button {
                    newTokenName = ""
                    showingAddToken = true
                } label: {
                    Label("Add Token", systemImage: "plus.circle")
                }
                .disabled(viewModel.mcpServerRunning == true)
            } header: {
                Label("API Tokens", systemImage: "key")
            } footer: {
                Text(viewModel.mcpServerRunning == true
                    ? "Stop the server to add or remove tokens."
                    : "Each client needs a unique Bearer token.")
            }

            // MARK: - OAuth Credentials
            OAuthCredentialsView(viewModel: viewModel)

            if viewModel.storage.mcpServerEnabled {
                Section {
                    Toggle("MCP Protocol", isOn: Binding(
                        get: { storage.mcpProtocolEnabled },
                        set: { newValue in
                            if !newValue && !storage.restApiEnabled {
                                storage.restApiEnabled = true
                            }
                            storage.mcpProtocolEnabled = newValue
                        }
                    ))
                    Toggle("REST API", isOn: Binding(
                        get: { storage.restApiEnabled },
                        set: { newValue in
                            if !newValue && !storage.mcpProtocolEnabled {
                                storage.mcpProtocolEnabled = true
                            }
                            storage.restApiEnabled = newValue
                        }
                    ))
                } header: {
                    Label("Protocols", systemImage: "point.3.connected.trianglepath.dotted")
                } footer: {
                    Text("Choose which protocols are available. At least one must be enabled.")
                }
            }

            if viewModel.mcpServerRunning == true {
                Section {
                    let displayHost = viewModel.storage.mcpServerBindAddress == "0.0.0.0"
                        ? viewModel.localIPAddress
                        : viewModel.storage.mcpServerBindAddress
                    if storage.mcpProtocolEnabled {
                        endpointRow(label: "MCP Streamable", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/mcp")
                        endpointRow(label: "MCP Legacy SSE", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/sse")
                    }
                    if storage.restApiEnabled {
                        endpointRow(label: "REST API", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/devices")
                    }
                } header: {
                    Label("Endpoints", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Server")
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
        .alert("Add API Token", isPresented: $showingAddToken) {
            TextField("Client name", text: $newTokenName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let name = newTokenName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                viewModel.addAPIToken(name: name)
            }
        } message: {
            Text("Enter a name to identify this client (e.g. Claude Desktop, Home Assistant).")
        }
        .alert("Delete Token?", isPresented: Binding(
            get: { tokenToDelete != nil },
            set: { if !$0 { tokenToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { tokenToDelete = nil }
            Button("Delete", role: .destructive) {
                if let token = tokenToDelete {
                    viewModel.deleteAPIToken(id: token.id)
                    tokenToDelete = nil
                }
            }
        } message: {
            if let token = tokenToDelete {
                Text("The client \"\(token.name)\" will no longer be able to authenticate. This cannot be undone.")
            }
        }
    }

    // MARK: - Token Row

    @ViewBuilder
    private func tokenRow(_ apiToken: APIToken) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(apiToken.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(apiToken.createdAt, style: .date)
                    .font(.footnote)
                    .foregroundColor(Theme.Text.tertiary)
            }

            HStack {
                let isRevealed = revealedTokenIds.contains(apiToken.id)
                if isRevealed {
                    Text(apiToken.token)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(String(repeating: "\u{2022}", count: 32))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    if revealedTokenIds.contains(apiToken.id) {
                        revealedTokenIds.remove(apiToken.id)
                    } else {
                        revealedTokenIds.insert(apiToken.id)
                    }
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    #if targetEnvironment(macCatalyst)
                    UIPasteboard.general.string = apiToken.token
                    #endif
                    showCopyToast()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    tokenToDelete = apiToken
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(viewModel.mcpServerRunning == true ? .secondary : .red)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.mcpServerRunning == true)
            }
        }
    }

    // MARK: - Helpers

    private func showCopyToast() {
        copiedToastTask?.cancel()
        showCopiedToast = true
        copiedToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { showCopiedToast = false }
        }
    }

    private func endpointRow(label: String, url: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .foregroundColor(Theme.Text.tertiary)
                Text(url)
                    .font(.system(.footnote, design: .monospaced))
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
                    .font(.footnote)
                    .foregroundColor(Theme.Tint.main)
            }
            .buttonStyle(.plain)
            .help("Copy URL")
        }
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
