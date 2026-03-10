import SwiftUI

struct WorkflowListView: View {
    @ObservedObject var viewModel: WorkflowViewModel
    var aiWorkflowService: AIWorkflowService?
    var aiEnabled: Bool = false

    @State private var showingEditor = false
    @State private var showingAIBuilder = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                if viewModel.workflows.isEmpty {
                    emptyState
                } else {
                    let devices = viewModel.devices
                    let scenes = viewModel.scenes
                    ForEach(viewModel.filteredWorkflows) { workflow in
                        NavigationLink(value: workflow.id) {
                            WorkflowRow(
                                workflow: workflow,
                                recentLogs: viewModel.executionLogs(for: workflow.id),
                                onToggle: { viewModel.toggleEnabled(id: workflow.id) },
                                onClone: { viewModel.cloneWorkflow(id: workflow.id) },
                                hasOrphanedReferences: Self.workflowHasOrphanedRefs(workflow, devices: devices, scenes: scenes)
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
                    Text("Workflow duplicated")
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
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer, prompt: "Search workflows")
        .navigationTitle("Workflows (\(viewModel.workflows.count))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if aiEnabled, aiWorkflowService != nil {
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
            WorkflowEditorView(
                mode: .create,
                devices: viewModel.devices,
                scenes: viewModel.scenes,
                workflows: viewModel.workflows,
                onSave: { draft in
                    viewModel.createWorkflow(from: draft)
                }
            )
        }
        .sheet(isPresented: $showingAIBuilder) {
            if let service = aiWorkflowService {
                WorkflowBuilderView(
                    aiWorkflowService: service,
                    devices: viewModel.devices,
                    scenes: viewModel.scenes,
                    onSave: { workflow in
                        viewModel.saveGeneratedWorkflow(workflow)
                    }
                )
            }
        }
        .navigationDestination(for: UUID.self) { workflowId in
            if let workflow = viewModel.workflows.first(where: { $0.id == workflowId }) {
                WorkflowDetailView(
                    workflow: workflow,
                    executionLogs: viewModel.executionLogs(for: workflowId),
                    devices: viewModel.devices,
                    scenes: viewModel.scenes,
                    workflows: viewModel.workflows,
                    onToggle: { viewModel.toggleEnabled(id: workflowId) },
                    onDelete: { viewModel.deleteWorkflow(id: workflowId) },
                    onTrigger: { viewModel.triggerWorkflow(id: workflowId) },
                    onUpdate: { draft in
                        viewModel.updateWorkflow(id: workflowId, from: draft)
                    },
                    onClone: { viewModel.cloneWorkflow(id: workflowId) },
                    onCancelExecution: { executionId in
                        viewModel.cancelExecution(executionId: executionId)
                    },
                    onResetStatistics: { viewModel.resetStatistics(id: workflowId) }
                )
            }
        }
    }

    private static func workflowHasOrphanedRefs(_ workflow: Workflow, devices: [DeviceModel], scenes: [SceneModel]) -> Bool {
        let deviceIds = Set(devices.map(\.id))
        let sceneIds = Set(scenes.map(\.id))
        let deviceRefs = WorkflowMigrationService.collectDeviceReferences(from: workflow)
        for ref in deviceRefs {
            if !deviceIds.contains(ref.deviceId) { return true }
        }
        let sceneRefs = WorkflowMigrationService.collectSceneReferences(from: workflow)
        for ref in sceneRefs {
            if !sceneIds.contains(ref.sceneId) { return true }
        }
        return false
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 16) {
                EmptyStateView(
                    icon: "bolt.circle",
                    title: "No workflows yet",
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
        WorkflowListView(viewModel: PreviewData.workflowViewModel)
    }
}
