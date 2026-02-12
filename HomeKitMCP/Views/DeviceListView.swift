import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: HomeKitViewModel

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
            } else if viewModel.isLoading && viewModel.totalDeviceCount == 0 {
                ProgressView("Discovering devices...")
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
            } else {
                List {
                    ForEach(viewModel.filteredDevicesByRoom, id: \.roomName) { group in
                        Section(header: 
                            Text(group.roomName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(Theme.Text.primary)
                                .padding(.vertical, 8)
                                .textCase(nil)
                        ) {
                            ForEach(group.devices) { device in
                                DeviceRow(device: device, viewModel: viewModel)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                                    .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Theme.mainBackground)
                .scrollContentBackground(.hidden)
                .searchable(text: $viewModel.searchText, prompt: "Search devices")
                .refreshable {
                    viewModel.refresh()
                }
            }
        }
        .navigationTitle("HomeKit Devices")
    }
}

#Preview {
    NavigationStack {
        DeviceListView(viewModel: PreviewData.homeKitViewModel)
    }
}
