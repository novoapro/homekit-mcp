import SwiftUI

struct LogViewerView: View {
    @ObservedObject var viewModel: LogViewModel
    var onCancelExecution: ((UUID) -> Void)?
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
                        EmptyStateView(
                            icon: "list.bullet.rectangle",
                            title: "No logs yet",
                            message: "Logs will appear here when devices change state or workflows execute."
                        )
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
                            ForEach(group.logs) { unifiedLog in
                                switch unifiedLog {
                                case .stateChange(let log):
                                    LogRow(log: log, detailedLogsEnabled: viewModel.detailedLogsEnabled)
                                        .listRowBackground(Theme.contentBackground)
                                case .workflowExecution(let log):
                                    NavigationLink {
                                        WorkflowExecutionLogDetailView(logId: log.id, viewModel: viewModel, onCancel: onCancelExecution)
                                    } label: {
                                        WorkflowExecutionLogRow(log: log)
                                    }
                                    .listRowBackground(Theme.contentBackground)
                                }
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
                        withAnimation(Theme.Animation.filter) {
                            viewModel.clearFilters()
                        }
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundColor(Theme.Status.error)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
    }

    private var categoryFilterChip: some View {
        FilterDropdown {
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
                    .font(.footnote)
                    .fontWeight(.medium)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Theme.Colors.chipInactive)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Button("All Categories") {
                    withAnimation { viewModel.selectedCategories.removeAll() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ForEach(LogCategoryFilter.allCases, id: \.self) { category in
                    if category != .all {
                        Button {
                            if viewModel.selectedCategories.contains(category) {
                                viewModel.selectedCategories.remove(category)
                            } else {
                                viewModel.selectedCategories.insert(category)
                            }
                        } label: {
                            HStack {
                                Label(category.rawValue, systemImage: category.icon)
                                    .foregroundColor(Theme.Text.primary)
                                Spacer()
                                if viewModel.selectedCategories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(Theme.Tint.main)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 230)
        }
    }

    private var deviceFilterChip: some View {
        FilterDropdown {
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
                    .font(.footnote)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Theme.Colors.chipInactive)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Button("All Devices") {
                    withAnimation { viewModel.selectedDevices.removeAll() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.availableDevices, id: \.self) { device in
                            Button {
                                if viewModel.selectedDevices.contains(device) {
                                    viewModel.selectedDevices.remove(device)
                                } else {
                                    viewModel.selectedDevices.insert(device)
                                }
                            } label: {
                                HStack {
                                    Text(device)
                                        .foregroundColor(Theme.Text.primary)
                                    Spacer()
                                    if viewModel.selectedDevices.contains(device) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.Tint.main)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.availableDevices.isEmpty {
                            Text("No devices found")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 210)
        }
    }

    private var serviceFilterChip: some View {
        FilterDropdown {
            let isActive = !viewModel.selectedServices.isEmpty
            HStack(spacing: 4) {
                Image(systemName: "gearshape.2")
                    .font(.caption2)
                let text: String = {
                    if viewModel.selectedServices.isEmpty { return "All Services" }
                    if viewModel.selectedServices.count == 1 { return viewModel.selectedServices.first! }
                    return "\(viewModel.selectedServices.count) Services"
                }()
                Text(text)
                    .font(.footnote)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : Theme.Colors.chipInactive)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.secondary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Button("All Services") {
                    withAnimation { viewModel.selectedServices.removeAll() }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.availableServices, id: \.self) { service in
                            Button {
                                if viewModel.selectedServices.contains(service) {
                                    viewModel.selectedServices.remove(service)
                                } else {
                                    viewModel.selectedServices.insert(service)
                                }
                            } label: {
                                HStack {
                                    Text(service)
                                        .foregroundColor(Theme.Text.primary)
                                    Spacer()
                                    if viewModel.selectedServices.contains(service) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Theme.Tint.main)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if viewModel.availableServices.isEmpty {
                            Text("No services found")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 210)
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView(viewModel: PreviewData.logViewModel)
    }
}
