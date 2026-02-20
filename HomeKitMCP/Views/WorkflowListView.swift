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
                    ForEach(viewModel.filteredWorkflows) { workflow in
                        NavigationLink(value: workflow.id) {
                            WorkflowRow(
                                workflow: workflow,
                                recentLogs: viewModel.executionLogs(for: workflow.id),
                                onToggle: { viewModel.toggleEnabled(id: workflow.id) }
                            )
                        }
                        .listRowBackground(Theme.contentBackground)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
        }
        .background(Theme.mainBackground)
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
                    onToggle: { viewModel.toggleEnabled(id: workflowId) },
                    onDelete: { viewModel.deleteWorkflow(id: workflowId) },
                    onTrigger: { viewModel.triggerWorkflow(id: workflowId) },
                    onUpdate: { draft in
                        viewModel.updateWorkflow(id: workflowId, from: draft)
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "bolt.circle")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No workflows yet")
                    .font(.headline)
                if aiEnabled {
                    Text("Tap + to create a workflow manually, or tap the sparkles icon to use the AI builder.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Tap + to create a workflow, or use an AI agent via MCP.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}
