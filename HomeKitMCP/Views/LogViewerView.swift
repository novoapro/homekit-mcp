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
            Button("All Categories") {
                withAnimation { viewModel.selectedCategories.removeAll() }
            }
            Divider()
            ForEach(LogCategoryFilter.allCases) { category in
                // Skip .all in the multi-select menu list if we have a separate "Clear/All" button, 
                // but checking it here usually means "Toggle this one". 
                // .all is a special case in the enum, might want to exclude it from the list if it represents "no filter".
                if category != .all {
                    Button {
                        withAnimation {
                            if viewModel.selectedCategories.contains(category) {
                                viewModel.selectedCategories.remove(category)
                            } else {
                                viewModel.selectedCategories.insert(category)
                            }
                        }
                    } label: {
                        if viewModel.selectedCategories.contains(category) {
                            Label(category.rawValue, systemImage: "checkmark")
                        } else {
                            Label(category.rawValue, systemImage: category.icon)
                        }
                    }
                }
            }
        } label: {
            let isActive = !viewModel.selectedCategories.isEmpty
            HStack(spacing: 4) {
                // Icon: use first selected or generic if multiple/empty
                let iconName: String = {
                    if let first = viewModel.selectedCategories.first, viewModel.selectedCategories.count == 1 {
                        return first.icon
                    }
                    return "line.3.horizontal.decrease.circle"
                }()
                
                Image(systemName: iconName)
                    .font(.caption2)
                
                let text: String = {
                    if viewModel.selectedCategories.isEmpty { return "All Categories" }
                    if viewModel.selectedCategories.count == 1 { return viewModel.selectedCategories.first!.rawValue }
                    return "\(viewModel.selectedCategories.count) Categories"
                }()
                
                Text(text)
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
                withAnimation { viewModel.selectedDevices.removeAll() }
            }
            Divider()
            ForEach(viewModel.availableDevices, id: \.self) { device in
                Button {
                    withAnimation {
                        if viewModel.selectedDevices.contains(device) {
                            viewModel.selectedDevices.remove(device)
                        } else {
                            viewModel.selectedDevices.insert(device)
                        }
                    }
                } label: {
                    if viewModel.selectedDevices.contains(device) {
                        Label(device, systemImage: "checkmark")
                    } else {
                        Text(device)
                    }
                }
            }
        } label: {
            let isActive = !viewModel.selectedDevices.isEmpty
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.caption2)
                let text: String = {
                    if viewModel.selectedDevices.isEmpty { return "All Devices" }
                    if viewModel.selectedDevices.count == 1 { return viewModel.selectedDevices.first! }
                    return "\(viewModel.selectedDevices.count) Devices"
                }()
                Text(text)
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
                withAnimation { viewModel.selectedServices.removeAll() }
            }
            Divider()
            ForEach(viewModel.availableServices, id: \.self) { service in
                Button {
                    withAnimation {
                        if viewModel.selectedServices.contains(service) {
                            viewModel.selectedServices.remove(service)
                        } else {
                            viewModel.selectedServices.insert(service)
                        }
                    }
                } label: {
                    if viewModel.selectedServices.contains(service) {
                        Label(service, systemImage: "checkmark")
                    } else {
                        Text(service)
                    }
                }
            }
        } label: {
            let isActive = !viewModel.selectedServices.isEmpty
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.caption2)
                 let text: String = {
                    if viewModel.selectedServices.isEmpty { return "All Services" }
                    if viewModel.selectedServices.count == 1 { return viewModel.selectedServices.first! }
                    return "\(viewModel.selectedServices.count) Services"
                }()
                Text(text)
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
