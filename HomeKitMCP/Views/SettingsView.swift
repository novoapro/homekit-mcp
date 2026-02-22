import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService
    @ObservedObject private var appleSignInService: AppleSignInService

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        self.storage = viewModel.storage
        self.appleSignInService = viewModel.appleSignInService
    }

    var body: some View {
        List {
            // App Logo + Name header
            Section {
                VStack(spacing: 12) {
                    Image("SidebarLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                    VStack(spacing: 2) {
                        Text("HomeKit MCP")
                            .font(.headline)
                            .foregroundColor(Theme.Text.primary)
                        Text("Control your home with AI")
                            .font(.caption)
                            .foregroundColor(Theme.Text.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Category rows
            Section {
                // Server
                NavigationLink {
                    ServerSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "server.rack",
                        iconColor: .blue,
                        title: "Server",
                        badge: serverBadge
                    )
                }

                // Webhooks
                NavigationLink {
                    WebhookSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "paperplane",
                        iconColor: .indigo,
                        title: "Webhooks",
                        badge: webhookBadge
                    )
                }

                // Workflows
                NavigationLink {
                    WorkflowSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        title: "Workflows",
                        badge: workflowBadge
                    )
                }

                // AI Assistant
                NavigationLink {
                    AIAssistantSettingsView(
                        viewModel: viewModel,
                        aiWorkflowService: viewModel.aiWorkflowService
                    )
                } label: {
                    settingsRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "AI Assistant",
                        badge: aiBadge
                    )
                }
            }

            Section {
                // General
                NavigationLink {
                    GeneralSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "gearshape",
                        iconColor: .gray,
                        title: "General",
                        badge: nil
                    )
                }

                // Account
                NavigationLink {
                    AccountSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "person.crop.circle",
                        iconColor: .blue,
                        title: "Account",
                        badge: accountBadge
                    )
                }
            }

            Section {
                // About
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    settingsRow(
                        icon: "info.circle",
                        iconColor: .secondary,
                        title: "About",
                        badge: aboutBadge
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .navigationTitle("Settings")
    }

    // MARK: - Status Badges

    private var serverBadge: StatusBadge? {
        guard let running = viewModel.mcpServerRunning else { return nil }
        if running {
            return StatusBadge(text: "Running", color: Theme.Status.active)
        } else {
            return StatusBadge(text: "Stopped", color: Theme.Status.inactive)
        }
    }

    private var webhookBadge: StatusBadge? {
        if !viewModel.webhookEnabled {
            return StatusBadge(text: "Off", color: Theme.Status.inactive)
        }
        if storage.isWebhookConfigured() {
            return StatusBadge(text: "Configured", color: Theme.Status.active)
        }
        return nil
    }

    private var workflowBadge: StatusBadge {
        if viewModel.workflowsEnabled {
            return StatusBadge(text: "On", color: Theme.Status.active)
        } else {
            return StatusBadge(text: "Off", color: Theme.Status.inactive)
        }
    }

    private var aiBadge: StatusBadge? {
        guard viewModel.aiEnabled else { return nil }
        if viewModel.aiApiKeyConfigured {
            return StatusBadge(text: "Enabled", color: Theme.Status.active)
        }
        return nil
    }

    private var accountBadge: StatusBadge? {
        if appleSignInService.isSignedIn {
            return StatusBadge(text: "Signed In", color: Theme.Status.active)
        }
        return nil
    }

    private var aboutBadge: StatusBadge {
        StatusBadge(text: "v1.0.0", color: Theme.Status.inactive)
    }

    // MARK: - Row Builder

    private func settingsRow(icon: String, iconColor: Color, title: String, badge: StatusBadge?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .foregroundColor(Theme.Text.primary)

            Spacer()

            if let badge {
                Text(badge.text)
                    .font(.subheadline)
                    .foregroundColor(badge.color)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Badge Model

private struct StatusBadge {
    let text: String
    let color: Color
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: PreviewData.settingsViewModel)
    }
}
