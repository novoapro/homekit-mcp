import SwiftUI

struct ServerSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService

    @State private var showingApiToken = false
    @State private var showingRegenerateConfirmation = false
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?

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
                        .font(.caption)
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
                }
                .disabled(viewModel.mcpServerRunning == true)
            } header: {
                Label("Network", systemImage: "network")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
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
            } header: {
                Label("API Token", systemImage: "key")
            } footer: {
                Text("All endpoints require an Authorization: Bearer <token> header.")
            }

            if viewModel.mcpServerRunning == true {
                Section {
                    let displayHost = viewModel.storage.mcpServerBindAddress == "0.0.0.0"
                        ? viewModel.localIPAddress
                        : viewModel.storage.mcpServerBindAddress
                    endpointRow(label: "MCP Streamable", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/mcp")
                    endpointRow(label: "MCP Legacy SSE", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/sse")
                    endpointRow(label: "REST API", url: "http://\(displayHost):\(viewModel.storage.mcpServerPort)/devices")
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
        .alert("Regenerate API Token?", isPresented: $showingRegenerateConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Regenerate", role: .destructive) {
                viewModel.regenerateMCPApiToken()
                showingApiToken = true
            }
        } message: {
            Text("All existing MCP clients will need to be updated with the new token. The server must be restarted for the new token to take effect.")
        }
    }

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
        ServerSettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
