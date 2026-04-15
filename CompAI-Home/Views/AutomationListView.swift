import SwiftUI
import Combine

struct AutomationListView: View {
    @ObservedObject var viewModel: AutomationViewModel
    var aiAutomationService: AIAutomationService?
    var aiEnabled: Bool = false
    @ObservedObject var subscriptionService: SubscriptionService
    var stateVariableStorage: StateVariableStorageService?

    @State private var showingEditor = false
    @State private var showingAIBuilder = false
    @State private var showingControllerStates = false
    @State private var loadedStates: [StateVariable] = []
    @State private var statesCancellable: AnyCancellable?

    private var isPro: Bool { subscriptionService.currentTier == .pro }

    var body: some View {
        if !isPro {
            proUpgradeContent
        } else {
            automationContent
        }
    }

    private var proUpgradeContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                ProUpgradePrompt(
                    featureName: "Automations",
                    description: "Create powerful automations with device state triggers, schedules, sunrise/sunset events, and webhook triggers. Go to Settings → Subscription to subscribe.",
                    onSubscribe: {
                        NotificationCenter.default.post(name: .navigateToSubscription, object: nil)
                    }
                )
                .padding()
            }
        }
        .background(Theme.mainBackground)
        .navigationTitle("Automations")
    }

    private var automationContent: some View {
        VStack(spacing: 0) {
            List {
                if stateVariableStorage != nil {
                    Button {
                        showingControllerStates = true
                    } label: {
                        HStack(spacing: 12) {
                            // 36x36 circle — same size as AutomationRow trigger icon
                            ZStack {
                                Circle()
                                    .fill(Theme.Tint.main.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cylinder.split.1x2.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.Tint.main)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Global Values")
                                    .font(.headline)
                                    .foregroundColor(Theme.Text.primary)
                                Text("Manage persistent state for your automations")
                                    .font(.footnote)
                                    .foregroundColor(Theme.Text.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.contentBackground)
                }

                if viewModel.automations.isEmpty {
                    emptyState
                } else {
                    let devices = viewModel.devices
                    let scenes = viewModel.scenes
                    ForEach(viewModel.filteredAutomations) { automation in
                        NavigationLink(value: automation.id) {
                            AutomationRow(
                                automation: automation,
                                recentLogs: viewModel.executionLogs(for: automation.id),
                                onToggle: { viewModel.toggleEnabled(id: automation.id) },
                                onClone: { viewModel.cloneAutomation(id: automation.id) },
                                hasOrphanedReferences: Self.automationHasOrphanedRefs(automation, devices: devices, scenes: scenes, stateNames: Set(loadedStates.map(\.name)))
                            )
                        }
                        .listRowBackground(Theme.contentBackground)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .refreshable {
                await viewModel.refresh()
            }
        }
        .refreshBar(isRefreshing: viewModel.isRefreshing)
        .background(Theme.mainBackground)
        .overlay(alignment: .bottom) {
            if viewModel.showClonedToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automation duplicated")
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
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.showClonedToast)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer, prompt: "Search automations")
        .task {
            if let storage = stateVariableStorage {
                loadedStates = await storage.getAll()
                statesCancellable = storage.variablesSubject.receive(on: DispatchQueue.main).sink { loadedStates = $0 }
            }
        }
        .navigationTitle("Automations (\(viewModel.automations.count))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if aiEnabled, aiAutomationService != nil {
                    Button {
                        showingAIBuilder = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                }

                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            AutomationEditorView(
                mode: .create,
                devices: viewModel.devices,
                scenes: viewModel.scenes,
                automations: viewModel.automations,
                controllerStates: loadedStates,
                onSave: { draft in
                    viewModel.createAutomation(from: draft)
                }
            )
        }
        .sheet(isPresented: $showingControllerStates) {
            if let storage = stateVariableStorage {
                NavigationStack {
                    StateVariablesView(storageService: storage, automations: viewModel.automations)
                }
            }
        }
        .sheet(isPresented: $showingAIBuilder) {
            if let service = aiAutomationService {
                AutomationBuilderView(
                    aiAutomationService: service,
                    devices: viewModel.devices,
                    scenes: viewModel.scenes,
                    onSave: { automation in
                        viewModel.saveGeneratedAutomation(automation)
                    }
                )
            }
        }
        .navigationDestination(for: UUID.self) { automationId in
            if let automation = viewModel.automations.first(where: { $0.id == automationId }) {
                AutomationDetailView(
                    automation: automation,
                    executionLogs: viewModel.executionLogs(for: automationId),
                    devices: viewModel.devices,
                    scenes: viewModel.scenes,
                    automations: viewModel.automations,
                    onToggle: { viewModel.toggleEnabled(id: automationId) },
                    onDelete: { viewModel.deleteAutomation(id: automationId) },
                    onTrigger: { viewModel.triggerAutomation(id: automationId) },
                    onUpdate: { draft in
                        viewModel.updateAutomation(id: automationId, from: draft)
                    },
                    onClone: { viewModel.cloneAutomation(id: automationId) },
                    onCancelExecution: { executionId in
                        viewModel.cancelExecution(executionId: executionId)
                    },
                    onResetStatistics: { viewModel.resetStatistics(id: automationId) },
                    onImproveWithAI: viewModel.aiAutomationService != nil ? { prompt in
                        try await viewModel.improveAutomation(id: automationId, prompt: prompt)
                    } : nil,
                    controllerStates: loadedStates
                )
            }
        }
    }

    private static func automationHasOrphanedRefs(_ automation: Automation, devices: [DeviceModel], scenes: [SceneModel], stateNames: Set<String> = []) -> Bool {
        let deviceIds = Set(devices.map(\.id))
        let sceneIds = Set(scenes.map(\.id))
        let deviceRefs = AutomationMigrationService.collectDeviceReferences(from: automation)
        for ref in deviceRefs {
            if !deviceIds.contains(ref.deviceId) { return true }
        }
        let sceneRefs = AutomationMigrationService.collectSceneReferences(from: automation)
        for ref in sceneRefs {
            if !sceneIds.contains(ref.sceneId) { return true }
        }
        // Check for references to deleted global values
        if !stateNames.isEmpty {
            let referencedNames = StateVariableReferenceScanner.collectReferencedStateNames(in: automation)
            for name in referencedNames {
                if !stateNames.contains(name) { return true }
            }
        }
        return false
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 16) {
                EmptyStateView(
                    icon: "bolt.circle",
                    title: "No automations yet",
                    message: aiEnabled
                        ? "Create automations with triggers, conditions, and actions to control your HomeKit devices."
                        : "Create automations with triggers, conditions, and actions, or use an AI agent via MCP.",
                    actions:  []
                )
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

#Preview {
    NavigationStack {
        AutomationListView(viewModel: PreviewData.automationViewModel, subscriptionService: SubscriptionService())
    }
}
