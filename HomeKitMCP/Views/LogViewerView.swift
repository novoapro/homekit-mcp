import SwiftUI

struct LogViewerView: View {
    @ObservedObject var viewModel: LogViewModel
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if !viewModel.hasLogs {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No state changes logged yet")
                            .font(.headline)
                        Text("Logs will appear here when HomeKit devices change state.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(viewModel.groupedLogs, id: \.date) { group in
                    Section(header: 
                        Text(group.label)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Text.primary)
                            .padding(.vertical, 8)
                            .textCase(nil)
                    ) {
                        ForEach(group.logs) { log in
                            LogRow(log: log)
                                .listRowBackground(Theme.contentBackground)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.mainBackground)
        .searchable(text: $viewModel.searchText, prompt: "Search by device or characteristic")
        .navigationTitle("Logs (\(viewModel.filteredLogCount))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear All") {
                    showingClearConfirmation = true
                }
                .disabled(!viewModel.hasLogs)
            }
        }
        .alert("Clear All Logs?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearLogs()
            }
        } message: {
            Text("This will permanently delete all logs.")
        }
    }
}

#Preview {
    NavigationStack {
        // Preview data might need adjustment if it doesn't match new VM structure perfectly, 
        // but passing a VM is what matters.
        LogViewerView(viewModel: LogViewModel(loggingService: LoggingService()))
    }
}

