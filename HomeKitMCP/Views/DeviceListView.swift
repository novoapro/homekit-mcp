import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: HomeKitViewModel

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
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Room filter
                roomFilterChip

                // Service type filter
                serviceTypeFilterChip

                // MCP filter
                triStateChip(
                    label: "MCP",
                    icon: "server.rack",
                    filter: $viewModel.mcpFilter
                )

                // Webhook filter
                triStateChip(
                    label: "Webhook",
                    icon: "bell.badge",
                    filter: $viewModel.webhookFilter
                )

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
                    
                }
            }
        }
    }

    private var roomFilterChip: some View {
        Menu {
            Button("All Rooms") {
                withAnimation { viewModel.selectedRooms.removeAll() }
            }
            Divider()
            ForEach(viewModel.availableRooms, id: \.self) { room in
                Button {
                    withAnimation {
                        if viewModel.selectedRooms.contains(room) {
                            viewModel.selectedRooms.remove(room)
                        } else {
                            viewModel.selectedRooms.insert(room)
                        }
                    }
                } label: {
                    if viewModel.selectedRooms.contains(room) {
                        Label(room, systemImage: "checkmark")
                    } else {
                        Text(room)
                    }
                }
            }
        } label: {
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
        }
    }

    private var serviceTypeFilterChip: some View {
        Menu {
            Button("All Types") {
                withAnimation { viewModel.selectedServiceTypes.removeAll() }
            }
            Divider()
            ForEach(viewModel.availableServiceTypes, id: \.self) { serviceType in
                Button {
                    withAnimation {
                        if viewModel.selectedServiceTypes.contains(serviceType) {
                            viewModel.selectedServiceTypes.remove(serviceType)
                        } else {
                            viewModel.selectedServiceTypes.insert(serviceType)
                        }
                    }
                } label: {
                    if viewModel.selectedServiceTypes.contains(serviceType) {
                        Label(serviceType, systemImage: "checkmark")
                    } else {
                        Text(serviceType)
                    }
                }
            }
        } label: {
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
        }
    }

    private func triStateChip(label: String, icon: String, filter: Binding<TriStateFilter>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                // Cycle: all → enabled → disabled → all
                switch filter.wrappedValue {
                case .all: filter.wrappedValue = .enabled
                case .enabled: filter.wrappedValue = .disabled
                case .disabled: filter.wrappedValue = .all
                }
            }
        } label: {
            let isActive = filter.wrappedValue != .all
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(isActive ? "\(label): \(filter.wrappedValue.rawValue)" : label)
                    .font(.caption)
                    .fontWeight(.medium)
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
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        DeviceListView(viewModel: PreviewData.homeKitViewModel)
    }
}
