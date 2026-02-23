import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: HomeKitViewModel

    /// When set from sidebar category selection, pre-filters the device list
    var initialCategoryFilter: SidebarCategory?
    /// When set from sidebar room selection, pre-filters the device list
    var initialRoomFilter: String?
    /// Called when the user clears all filters — lets the sidebar know to reset its selection
    var onFiltersCleared: (() -> Void)?

    @State private var showBulkConfirm = false
    @State private var pendingBulkAction: (() -> Void)?
    @State private var bulkConfirmMessage = ""

    private var filteredDeviceCount: Int {
        viewModel.filteredDevicesByRoom.reduce(0) { $0 + $1.devices.count }
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "HomeKit Access Required",
                    message: error,
                    iconColor: Color.orange
                )
                .background(Theme.mainBackground)
            } else if viewModel.isLoading && viewModel.totalDeviceCount == 0 {
                ProgressView("Discovering devices...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.totalDeviceCount == 0 {
                EmptyStateView(
                    icon: "house",
                    title: "No HomeKit devices found",
                    message: "Make sure you have devices set up in the Home app."
                )
                .background(Theme.mainBackground)
            } else {
                VStack(spacing: 0) {
                    // Filter bar
                    filterBar
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    List {
                        ForEach(viewModel.filteredDevicesByRoom, id: \.roomName) { group in
                            Section(header:
                                HStack(spacing: 6) {
                                    Text(group.roomName)
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(Theme.Text.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.Text.tertiary)
                                    Spacer()
                                    Text("\(group.devices.count)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.Text.secondary)
                                }
                                .padding(.top, 5)
                                .padding(.bottom, 5)
                                .padding(.horizontal, 20)
                                .background(Theme.mainBackground.opacity(0.95))
                                .textCase(nil)
                                .listRowInsets(EdgeInsets())
                            ) {
                                ForEach(Array(group.devices.enumerated()), id: \.element.id) { index, device in
                                    let isFirst = index == 0
                                    let isLast = index == group.devices.count - 1

                                    VStack(spacing: 0) {
                                        DeviceRow(device: device, viewModel: viewModel)
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                    }
                                    .background(Theme.contentBackground)
                                    .clipShape(
                                        .rect(
                                            topLeadingRadius: isFirst ? 12 : 0,
                                            bottomLeadingRadius: isLast ? 12 : 0,
                                            bottomTrailingRadius: isLast ? 12 : 0,
                                            topTrailingRadius: isFirst ? 12 : 0
                                        )
                                    )
                                    .padding(.horizontal, 16)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Theme.mainBackground)
                }
                .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search devices")
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading || viewModel.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Bulk actions moved to toolbar menu
            if filteredDeviceCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        let allApiEnabled = viewModel.filteredDevicesByRoom.flatMap(\.devices).allSatisfy { viewModel.isExternalAccessEnabled(for: $0) }
                        let allWebhookEnabled = viewModel.filteredDevicesByRoom.flatMap(\.devices).allSatisfy { viewModel.isWebhookEnabled(for: $0) }

                        Section("API Access") {
                            Button {
                                confirmBulkAction(message: "Enable API for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(externalAccessEnabled: true)
                                }
                            } label: {
                                Label("Enable All", systemImage: allApiEnabled ? "checkmark.circle.fill" : "circle")
                            }
                            .disabled(allApiEnabled)

                            Button {
                                confirmBulkAction(message: "Disable API for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(externalAccessEnabled: false)
                                }
                            } label: {
                                Label("Disable All", systemImage: !allApiEnabled ? "xmark.circle" : "circle")
                            }
                            .disabled(!allApiEnabled)
                        }

                        Section("Webhooks") {
                            Button {
                                confirmBulkAction(message: "Enable Webhooks for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(webhookEnabled: true)
                                }
                            } label: {
                                Label("Enable All", systemImage: allWebhookEnabled ? "checkmark.circle.fill" : "circle")
                            }
                            .disabled(allWebhookEnabled)

                            Button {
                                confirmBulkAction(message: "Disable Webhooks for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(webhookEnabled: false)
                                }
                            } label: {
                                Label("Disable All", systemImage: !allWebhookEnabled ? "xmark.circle" : "circle")
                            }
                            .disabled(!allWebhookEnabled)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .background(Theme.mainBackground)
        .alert("Confirm Bulk Action", isPresented: $showBulkConfirm) {
            Button("Apply", role: .destructive) {
                pendingBulkAction?()
                pendingBulkAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBulkAction = nil
            }
        } message: {
            Text(bulkConfirmMessage)
        }
        .onAppear {
            applySidebarFilters()
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        if let category = initialCategoryFilter {
            return "\(category.label) (\(filteredDeviceCount))"
        } else if let room = initialRoomFilter {
            return "\(room) (\(filteredDeviceCount))"
        }
        return "Devices (\(filteredDeviceCount))"
    }

    // MARK: - Sidebar Filter Application

    private func applySidebarFilters() {
        if let category = initialCategoryFilter {
            // Filter by category type — map to service types that belong to this category
            let allDevices = viewModel.devicesByRoom.flatMap(\.devices)
            let matchingTypes = allDevices
                .filter { category.matchingCategoryTypes.contains($0.categoryType) }
                .flatMap { $0.services.map { ServiceTypes.displayName(for: $0.type) } }
            viewModel.selectedServiceTypes = Set(matchingTypes)
        } else if let room = initialRoomFilter {
            viewModel.selectedRooms = [room]
        }
    }

    // MARK: - Bulk Actions

    private func confirmBulkAction(message: String, action: @escaping () -> Void) {
        bulkConfirmMessage = message
        pendingBulkAction = action
        showBulkConfirm = true
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Room filter
                roomFilterChip

                // Service type filter
                serviceTypeFilterChip

                // API filter
                apiFilterChip

                // Webhook filter
                webhookFilterChip

                // Clear button
                if viewModel.hasActiveFilters {
                    Button {
                        withAnimation(Theme.Animation.filter) {
                            viewModel.clearFilters()
                            onFiltersCleared?()
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
                }
            }
        }
    }

    private var roomFilterChip: some View {
        FilterDropdown {
            let isActive = !viewModel.selectedRooms.isEmpty
            HStack(spacing: 4) {
                Image(systemName: "house")
                    .font(.caption2)
                let text: String = {
                    if viewModel.selectedRooms.isEmpty { return "All Rooms" }
                    if viewModel.selectedRooms.count == 1 { return viewModel.selectedRooms.first! }
                    return "\(viewModel.selectedRooms.count) Rooms"
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
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                menuRow(title: "All Rooms", isSelected: viewModel.selectedRooms.isEmpty) {
                    withAnimation { viewModel.selectedRooms.removeAll() }
                    if initialRoomFilter != nil { onFiltersCleared?() }
                }

                Divider()
                    .padding(.vertical, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.availableRooms, id: \.self) { room in
                            menuRow(title: room, isSelected: viewModel.selectedRooms.contains(room)) {
                                if viewModel.selectedRooms.contains(room) {
                                    viewModel.selectedRooms.remove(room)
                                } else {
                                    viewModel.selectedRooms.insert(room)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 230)
            .padding(.vertical, 4)
        }
    }

    private var serviceTypeFilterChip: some View {
        FilterDropdown {
            let isActive = !viewModel.selectedServiceTypes.isEmpty
            HStack(spacing: 4) {
                Image(systemName: "cube")
                    .font(.caption2)
                let text: String = {
                    if viewModel.selectedServiceTypes.isEmpty { return "All Types" }
                    if viewModel.selectedServiceTypes.count == 1 { return viewModel.selectedServiceTypes.first! }
                    return "\(viewModel.selectedServiceTypes.count) Types"
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
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                menuRow(title: "All Types", isSelected: viewModel.selectedServiceTypes.isEmpty) {
                    withAnimation { viewModel.selectedServiceTypes.removeAll() }
                }

                Divider()
                    .padding(.vertical, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.availableServiceTypes, id: \.self) { serviceType in
                            menuRow(title: serviceType, isSelected: viewModel.selectedServiceTypes.contains(serviceType)) {
                                if viewModel.selectedServiceTypes.contains(serviceType) {
                                    viewModel.selectedServiceTypes.remove(serviceType)
                                } else {
                                    viewModel.selectedServiceTypes.insert(serviceType)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .frame(width: 230)
            .padding(.vertical, 4)
        }
    }

    private var apiFilterChip: some View {
        FilterDropdown {
            let isActive = viewModel.mcpFilter != .all
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.caption2)
                Text(isActive ? "API: \(viewModel.mcpFilter.rawValue)" : "API")
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
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TriStateFilter.allCases, id: \.self) { option in
                    menuRow(title: option.rawValue, isSelected: viewModel.mcpFilter == option) {
                        viewModel.mcpFilter = option
                    }
                }
            }
            .frame(width: 210)
            .padding(.vertical, 4)
        }
    }

    private var webhookFilterChip: some View {
        FilterDropdown {
            let isActive = viewModel.webhookFilter != .all
            HStack(spacing: 4) {
                Image(systemName: "bell.badge")
                    .font(.caption2)
                Text(isActive ? "Webhook: \(viewModel.webhookFilter.rawValue)" : "Webhook")
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
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TriStateFilter.allCases, id: \.self) { option in
                    menuRow(title: option.rawValue, isSelected: viewModel.webhookFilter == option) {
                        viewModel.webhookFilter = option
                    }
                }
            }
            .frame(width: 230)
            .padding(.vertical, 4)
        }
    }

    private func menuRow(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.Text.primary)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 12)
                }

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(Theme.Text.secondary)
                }

                Text(title)
                    .foregroundColor(Theme.Text.primary)

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        DeviceListView(viewModel: PreviewData.homeKitViewModel)
    }
}

struct FilterDropdown<Label: View, Content: View>: View {
    let label: () -> Label
    let content: () -> Content

    @State private var isPresented = false

    init(@ViewBuilder label: @escaping () -> Label, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(Theme.contentBackground)
            .frame(minWidth: 200)
        }
    }
}
