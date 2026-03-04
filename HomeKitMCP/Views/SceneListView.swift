import SwiftUI

struct SceneListView: View {
    @ObservedObject var viewModel: HomeKitViewModel
    @State private var selectedScene: SceneModel?

    var body: some View {
        VStack(spacing: 0) {
            List {
                if viewModel.scenes.isEmpty {
                    EmptyStateView(
                        icon: "play.rectangle",
                        title: "No Scenes Found",
                        message: "Scenes created in the Home app will appear here. You can view and execute them."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.filteredScenes) { scene in
                        SceneRow(scene: scene) {
                            Task { await viewModel.executeScene(id: scene.id) }
                        }
                        .listRowBackground(Theme.contentBackground)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedScene = scene
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .refreshable {
                await viewModel.refreshAsync()
            }
        }
        .refreshBar(isRefreshing: viewModel.isRefreshing)
        .background(Theme.mainBackground)
        .searchable(text: $viewModel.sceneSearchText, placement: .navigationBarDrawer, prompt: "Search scenes")
        .navigationTitle("Scenes (\(viewModel.scenes.count))")
        .sheet(item: $selectedScene) { scene in
            SceneDetailSheet(scene: scene) {
                Task { await viewModel.executeScene(id: scene.id) }
            }
        }
    }
}

// MARK: - Scene Detail Sheet

private struct SceneDetailSheet: View {
    let scene: SceneModel
    let onExecute: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Type")
                            .foregroundColor(Theme.Text.secondary)
                        Spacer()
                        Text(scene.type)
                            .foregroundColor(Theme.Text.primary)
                    }
                    HStack {
                        Text("Actions")
                            .foregroundColor(Theme.Text.secondary)
                        Spacer()
                        Text("\(scene.actions.count)")
                            .foregroundColor(Theme.Text.primary)
                    }
                    if scene.isExecuting {
                        HStack {
                            Text("Status")
                                .foregroundColor(Theme.Text.secondary)
                            Spacer()
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Executing")
                                    .foregroundColor(Theme.Status.active)
                            }
                        }
                    }
                } header: {
                    Text("Details")
                }

                if !scene.actions.isEmpty {
                    Section {
                        ForEach(scene.actions) { action in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(action.deviceName)
                                    .font(.headline)
                                    .foregroundColor(Theme.Text.primary)
                                HStack {
                                    Text(action.characteristicType)
                                        .font(.subheadline)
                                        .foregroundColor(Theme.Text.secondary)
                                    Spacer()
                                    Text(formatTargetValue(action.targetValue))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.Tint.main)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Actions")
                    }
                }
            }
            .navigationTitle(scene.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onExecute()
                        dismiss()
                    } label: {
                        Label("Execute", systemImage: "play.fill")
                    }
                    .disabled(scene.isExecuting)
                }
            }
        }
    }

    private func formatTargetValue(_ value: AnyCodable) -> String {
        if let boolVal = value.value as? Bool {
            return boolVal ? "On" : "Off"
        }
        if let intVal = value.value as? Int {
            return "\(intVal)"
        }
        if let doubleVal = value.value as? Double {
            return String(format: "%.1f", doubleVal)
        }
        if let strVal = value.value as? String {
            return strVal
        }
        return "\(value.value)"
    }
}

#Preview {
    NavigationStack {
        SceneListView(viewModel: PreviewData.homeKitViewModel)
    }
}
