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
            } else if viewModel.isLoading {
                ProgressView("Discovering devices...")
            } else if viewModel.totalDeviceCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "house")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No HomeKit devices found")
                        .font(.headline)
                    Text("Make sure you have devices set up in the Home app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(viewModel.devicesByRoom, id: \.roomName) { group in
                        Section(header: Text(group.roomName)) {
                            ForEach(group.devices) { device in
                                DeviceRow(device: device)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("HomeKit Devices")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.refresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeviceListView(viewModel: PreviewData.homeKitViewModel)
    }
}
