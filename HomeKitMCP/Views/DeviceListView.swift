import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: HomeKitViewModel

    @State private var showBulkConfirm = false
    @State private var pendingBulkAction: (() -> Void)?
    @State private var bulkConfirmMessage = ""

    private var filteredDeviceCount: Int {
        viewModel.filteredDevicesByRoom.reduce(0) { $0 + $1.devices.count }
    }

    var body: some View {
        Group {
            if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("HomeKit Access Required")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.mainBackground)
            } else if viewModel.isLoading && viewModel.totalDeviceCount == 0 {
                ProgressView("Discovering devices...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.totalDeviceCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "house")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.3))
                        .padding(.bottom, 8)
                    Text("No HomeKit devices found")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Make sure you have devices set up in the Home app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    Text("(\(group.devices.count))")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(Theme.Text.secondary)
                                    Spacer()
                                }
                                .padding(.top, 5)
                                .padding(.bottom, 5)
                                .padding(.horizontal, 20) // Align with inset row content
                                .background(Theme.mainBackground.opacity(0.95)) // Slightly translucent sticky header
                                .textCase(nil)
                                .listRowInsets(EdgeInsets()) // Remove default header padding/insets
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
        .navigationTitle("HomeKit Devices (\(filteredDeviceCount))")
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
    }

    // MARK: - Bulk Action Bar



    private func bulkButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1)
            )
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }

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

                // EXT filter
                extFilterChip

                // Webhook filter
                webhookFilterChip
                
                // Bulk Actions & Clear (Only when filtered)
                if viewModel.hasActiveFilters {
                    // Clear all
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
                    
                    // Separator for visual distinction
                    Spacer()
                    
                    HStack{
                        // Bulk EXT Toggle
                        let allExtEnabled = viewModel.filteredDevicesByRoom.flatMap(\.devices).allSatisfy { viewModel.isExternalAccessEnabled(for: $0) }
                        
                        
                        
                        MiniToggle(isOn: Binding(
                            get: { allExtEnabled },
                            set: { newValue in
                                confirmBulkAction(message: newValue ? "Enable EXT for \(filteredDeviceCount) devices?" : "Disable EXT for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(externalAccessEnabled: newValue)
                                }
                            }
                        ), label: "Bulk EXT")
                        
                        // Bulk Webhook Toggle
                        let allHookEnabled = viewModel.filteredDevicesByRoom.flatMap(\.devices).allSatisfy { viewModel.isWebhookEnabled(for: $0) }
                        MiniToggle(isOn: Binding(
                            get: { allHookEnabled },
                            set: { newValue in
                                confirmBulkAction(message: newValue ? "Enable Webhooks for \(filteredDeviceCount) devices?" : "Disable Webhooks for \(filteredDeviceCount) devices?") {
                                    viewModel.setBulkConfig(webhookEnabled: newValue)
                                }
                            }
                        ), label: "Bulk Hook")
                    }
                    .padding(4)
                    .background(
                        Capsule()
                            .fill(Theme.Tint.main.opacity(0.15))
                    )
                    
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
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : .clear)
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
            .frame(width: 220)
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
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : .clear)
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
            .frame(width: 220)
            .padding(.vertical, 4)
        }
    }

    private var extFilterChip: some View {
        FilterDropdown {
            let isActive = viewModel.mcpFilter != .all
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                    .font(.caption2)
                Text(isActive ? "EXT: \(viewModel.mcpFilter.rawValue)" : "EXT")
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Filter Options
                ForEach(TriStateFilter.allCases, id: \.self) { option in
                    menuRow(title: option.rawValue, isSelected: viewModel.mcpFilter == option) {
                        viewModel.mcpFilter = option
                    }
                }
            }
            .frame(width: 200)
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
                    .font(.caption)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? Theme.Tint.main.opacity(0.15) : .clear)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? Theme.Tint.main : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isActive ? Theme.Tint.main : Theme.Text.primary)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Filter Options
                ForEach(TriStateFilter.allCases, id: \.self) { option in
                    menuRow(title: option.rawValue, isSelected: viewModel.webhookFilter == option) {
                        viewModel.webhookFilter = option
                    }
                }
            }
            .frame(width: 220)
            .padding(.vertical, 4)
        }
    }

    private func menuRow(title: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Text.primary)
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12, height: 10)
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
            // Removed default padding to allow rows to touch edges
             // .padding(.vertical, 8) 
            .background(Theme.contentBackground)
            // Ensure a minimum width for usability, but allow it to grow
            .frame(minWidth: 200) 
        }
    }
}
