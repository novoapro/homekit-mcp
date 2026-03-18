import SwiftUI

struct OAuthCredentialsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @State private var showingAddCredential = false
    @State private var newCredentialName = ""
    @State private var createdCredential: OAuthCredential?
    @State private var credentialToRevoke: OAuthCredential?
    @State private var credentialToDelete: OAuthCredential?
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?

    var body: some View {
        Section {
            ForEach(viewModel.oauthCredentials) { credential in
                credentialRow(credential)
            }

            Button {
                newCredentialName = ""
                showingAddCredential = true
            } label: {
                Label("Add OAuth Credential", systemImage: "plus.circle")
            }
        } header: {
            Label("OAuth Credentials", systemImage: "lock.shield")
        } footer: {
            Text("OAuth 2.1 credentials for MCP clients. Each credential generates a client ID and secret for the OAuth flow.")
        }
        .alert("Add OAuth Credential", isPresented: $showingAddCredential) {
            TextField("Client name", text: $newCredentialName)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                let name = newCredentialName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                createdCredential = viewModel.addOAuthCredential(name: name)
            }
        } message: {
            Text("Enter a name to identify this client (e.g. Claude Desktop).")
        }
        .alert("OAuth Credential Created", isPresented: Binding(
            get: { createdCredential != nil },
            set: { if !$0 { createdCredential = nil } }
        )) {
            Button("Copy Configuration") {
                if let cred = createdCredential {
                    let port = viewModel.storage.mcpServerPort
                    let config = """
                    Client ID: \(cred.clientId)
                    Client Secret: \(cred.clientSecret)
                    Token Endpoint: http://localhost:\(port)/oauth/token
                    Authorization Endpoint: http://localhost:\(port)/oauth/authorize
                    """
                    #if targetEnvironment(macCatalyst)
                    UIPasteboard.general.string = config
                    #endif
                }
                createdCredential = nil
            }
            Button("Close", role: .cancel) { createdCredential = nil }
        } message: {
            if let cred = createdCredential {
                Text("Client ID: \(cred.clientId)\n\nClient Secret: \(cred.clientSecret)\n\nSave these now — the secret won't be shown again.")
            }
        }
        .alert("Revoke Credential?", isPresented: Binding(
            get: { credentialToRevoke != nil },
            set: { if !$0 { credentialToRevoke = nil } }
        )) {
            Button("Cancel", role: .cancel) { credentialToRevoke = nil }
            Button("Revoke", role: .destructive) {
                if let credential = credentialToRevoke {
                    viewModel.revokeOAuthCredential(id: credential.id)
                    credentialToRevoke = nil
                }
            }
        } message: {
            if let credential = credentialToRevoke {
                Text("All active sessions for \"\(credential.name)\" will be terminated immediately.")
            }
        }
        .alert("Delete Credential?", isPresented: Binding(
            get: { credentialToDelete != nil },
            set: { if !$0 { credentialToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { credentialToDelete = nil }
            Button("Delete", role: .destructive) {
                if let credential = credentialToDelete {
                    viewModel.deleteOAuthCredential(id: credential.id)
                    credentialToDelete = nil
                }
            }
        } message: {
            if let credential = credentialToDelete {
                Text("The credential \"\(credential.name)\" will be permanently deleted. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func credentialRow(_ credential: OAuthCredential) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(credential.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(credential.isRevoked ? .secondary : .primary)

                if credential.isRevoked {
                    Text("REVOKED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1), in: Capsule())
                }

                Spacer()

                Text(credential.createdAt, style: .date)
                    .font(.footnote)
                    .foregroundColor(Theme.Text.tertiary)
            }

            HStack {
                Text("ID: \(String(credential.clientId.prefix(16)))...")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                if let lastUsed = credential.lastUsedAt {
                    Text("Last used \(lastUsed, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(Theme.Text.tertiary)
                }
            }

            HStack {
                Spacer()

                if !credential.isRevoked {
                    Button {
                        credentialToRevoke = credential
                    } label: {
                        Image(systemName: "xmark.shield")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Revoke credential")
                }

                Button {
                    credentialToDelete = credential
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete credential")
            }
        }
        .opacity(credential.isRevoked ? 0.6 : 1.0)
    }
}
