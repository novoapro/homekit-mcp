import Foundation
import HomeKit
import Combine

class HomeKitViewModel: ObservableObject {
    @Published var devicesByRoom: [(roomName: String, devices: [DeviceModel])] = []
    @Published var isLoading = true
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var errorMessage: String?

    private let homeKitManager: HomeKitManager
    private var cancellables = Set<AnyCancellable>()

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var totalDeviceCount: Int {
        devicesByRoom.reduce(0) { $0 + $1.devices.count }
    }

    init(homeKitManager: HomeKitManager) {
        self.homeKitManager = homeKitManager

        homeKitManager.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if isReady {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        homeKitManager.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorizationStatus = status
                self?.updateErrorForStatus(status)
            }
            .store(in: &cancellables)

        homeKitManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        devicesByRoom = homeKitManager.getDevicesGroupedByRoom()
        isLoading = false
    }

    private func updateErrorForStatus(_ status: HMHomeManagerAuthorizationStatus) {
        if status == .restricted {
            errorMessage = "HomeKit access is restricted on this device."
        } else if !status.contains(.authorized) && homeKitManager.isReady {
            errorMessage = "HomeKit access was denied. Grant access in System Settings > Privacy & Security > HomeKit."
        } else {
            errorMessage = nil
        }
    }
}
