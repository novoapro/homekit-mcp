import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var storage: StorageService
    @ObservedObject private var appleSignInService: AppleSignInService
    @ObservedObject private var subscriptionService: SubscriptionService
    @Binding var navigateToSubscription: Bool
    @State private var unresolvedCount = 0
    @State private var showAccount = false

    init(viewModel: SettingsViewModel, navigateToSubscription: Binding<Bool> = .constant(false)) {
        self.viewModel = viewModel
        self.storage = viewModel.storage
        self.appleSignInService = viewModel.appleSignInService
        self.subscriptionService = viewModel.subscriptionService
        self._navigateToSubscription = navigateToSubscription
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
                        Text("CompAI - Home")
                            .font(.headline)
                            .foregroundColor(Theme.Text.primary)
                        Text("AI that feels at home")
                            .font(.footnote)
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

                // Automations
                NavigationLink {
                    AutomationSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        title: "Automation+",
                        badge: automationBadge
                    )
                }

                // AI Assistant
                NavigationLink {
                    AIAssistantSettingsView(
                        viewModel: viewModel,
                        aiAutomationService: viewModel.aiAutomationService
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

                // Device Registry
                NavigationLink {
                    OrphanedDevicesView(
                        registryService: viewModel.deviceRegistryService,
                        homeKitManager: viewModel.homeKitManager,
                        automationStorageService: viewModel.automationStorageService,
                        viewModel: viewModel
                    )
                } label: {
                    settingsRow(
                        icon: "externaldrive.connected.to.line.below",
                        iconColor: .gray,
                        title: "Device Registry",
                        badge: registryBadge
                    )
                }

                // Account & Subscription
                NavigationLink(isActive: $showAccount) {
                    AccountSettingsView(viewModel: viewModel)
                } label: {
                    settingsRow(
                        icon: subscriptionService.currentTier == .pro ? "crown.fill" : "person.crop.circle",
                        iconColor: subscriptionService.currentTier == .pro ? .yellow : .blue,
                        title: "Account",
                        badge: subscriptionBadge
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
        .task {
            let devices = await viewModel.deviceRegistryService.unresolvedDevices()
            let scenes = await viewModel.deviceRegistryService.unresolvedScenes()
            unresolvedCount = devices.count + scenes.count
        }
        .onChange(of: navigateToSubscription) { navigate in
            if navigate {
                showAccount = true
                navigateToSubscription = false
            }
        }
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

    private var automationBadge: StatusBadge {
        if viewModel.automationsEnabled {
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

    private var registryBadge: StatusBadge? {
        guard unresolvedCount > 0 else { return nil }
        return StatusBadge(text: "\(unresolvedCount) unresolved", color: .orange)
    }

    private var accountBadge: StatusBadge? {
        if appleSignInService.isSignedIn {
            return StatusBadge(text: "Signed In", color: Theme.Status.active)
        }
        return nil
    }

    private var subscriptionBadge: StatusBadge {
        if subscriptionService.currentTier == .pro {
            return StatusBadge(text: "Pro", color: Theme.Status.active)
        } else {
            return StatusBadge(text: "Free", color: Theme.Status.inactive)
        }
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
