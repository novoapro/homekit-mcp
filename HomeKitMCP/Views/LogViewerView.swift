import SwiftUI

struct LogViewerView: View {
    @ObservedObject var viewModel: LogViewModel
    @State private var searchText = ""
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if viewModel.logs.isEmpty {
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
                ForEach(groupedByDate, id: \.date) { group in
                    Section(header: Text(group.label)) {
                        ForEach(group.logs) { log in
                            LogRow(log: log)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by device or characteristic")
        .navigationTitle("Logs (\(viewModel.logs.count))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear All") {
                    showingClearConfirmation = true
                }
                .disabled(viewModel.logs.isEmpty)
            }
        }
        .alert("Clear All Logs?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearLogs()
            }
        } message: {
            Text("This will permanently delete all \(viewModel.logs.count) log entries.")
        }
    }

    private var filteredLogs: [StateChangeLog] {
        if searchText.isEmpty {
            return viewModel.logs
        }
        let query = searchText.lowercased()
        return viewModel.logs.filter { log in
            log.deviceName.localizedCaseInsensitiveContains(query) ||
            CharacteristicTypes.displayName(for: log.characteristicType)
                .localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedByDate: [(date: String, label: String, logs: [StateChangeLog])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let grouped = Dictionary(grouping: filteredLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (date, logs) in
                let label: String
                if calendar.isDateInToday(date) {
                    label = "Today"
                } else if calendar.isDateInYesterday(date) {
                    label = "Yesterday"
                } else {
                    label = formatter.string(from: date)
                }
                return (date: date.ISO8601Format(), label: label, logs: logs)
            }
    }
}

#Preview {
    NavigationStack {
        LogViewerView(viewModel: PreviewData.logViewModel)
    }
}

