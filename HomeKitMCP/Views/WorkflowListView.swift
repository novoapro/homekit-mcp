import SwiftUI

struct WorkflowListView: View {
    @ObservedObject var viewModel: WorkflowViewModel

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
        .navigationDestination(for: UUID.self) { workflowId in
            if let workflow = viewModel.workflows.first(where: { $0.id == workflowId }) {
                WorkflowDetailView(
                    workflow: workflow,
                    executionLogs: viewModel.executionLogs(for: workflowId),
                    onToggle: { viewModel.toggleEnabled(id: workflowId) },
                    onDelete: { viewModel.deleteWorkflow(id: workflowId) },
                    onTrigger: { viewModel.triggerWorkflow(id: workflowId) }
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
                Text("Use an AI agent to create workflows via MCP, or add them through the REST API.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}
