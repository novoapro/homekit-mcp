import SwiftUI

struct LogViewerView: View {
    @ObservedObject var viewModel: LogViewModel
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            if viewModel.hasLogs {
                logFilterBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
        }
        .background(Theme.mainBackground)
        .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer, prompt: "Search by device, service or characteristic")
        .navigationTitle("Logs (\(viewModel.filteredLogCount))")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
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

    // MARK: - Filter Bar

    private var logFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Category filter
                categoryFilterChip

                // Device filter
                deviceFilterChip

                // Service filter
                if !viewModel.availableServices.isEmpty {
                    serviceFilterChip
                }

                // Clear all
                if viewModel.hasActiveFilters {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.clearFilters()
                        }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.Status.error)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
    }

    private var categoryFilterChip: some View {
        Menu {
            ForEach(LogCategoryFilter.allCases) { category in
                Button {
                    withAnimation { viewModel.selectedCategory = category }
                } label: {
                    if viewModel.selectedCategory == category {
                        Label(category.rawValue, systemImage: "checkmark")
                    } else {
                        Label(category.rawValue, systemImage: category.icon)
                    }
                }
            }
        } label: {
            let isActive = viewModel.selectedCategory != .all
            HStack(spacing: 4) {
                Image(systemName: viewModel.selectedCategory.icon)
                    .font(.caption2)
                Text(viewModel.selectedCategory.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        }
    }

    private var deviceFilterChip: some View {
        Menu {
            Button("All Devices") {
                withAnimation { viewModel.selectedDevice = nil }
            }
            Divider()
            ForEach(viewModel.availableDevices, id: \.self) { device in
                Button {
                    withAnimation { viewModel.selectedDevice = device }
                } label: {
                    if viewModel.selectedDevice == device {
                        Label(device, systemImage: "checkmark")
                    } else {
                        Text(device)
                    }
                }
            }
        } label: {
            let isActive = viewModel.selectedDevice != nil
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.caption2)
                Text(viewModel.selectedDevice ?? "All Devices")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        }
    }

    private var serviceFilterChip: some View {
        Menu {
            Button("All Services") {
                withAnimation { viewModel.selectedService = nil }
            }
            Divider()
            ForEach(viewModel.availableServices, id: \.self) { service in
                Button {
                    withAnimation { viewModel.selectedService = service }
                } label: {
                    if viewModel.selectedService == service {
                        Label(service, systemImage: "checkmark")
                    } else {
                        Text(service)
                    }
                }
            }
        } label: {
            let isActive = viewModel.selectedService != nil
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.caption2)
                Text(viewModel.selectedService ?? "All Services")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Color(.systemGray6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView(viewModel: LogViewModel(loggingService: LoggingService()))
    }
}
