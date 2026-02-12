import Foundation
import HomeKit
import Combine

class HomeKitViewModel: ObservableObject {
    @Published var devicesByRoom: [(roomName: String, devices: [DeviceModel])] = []
    @Published var isLoading = true
    @Published var isReadingValues = false
    @Published var authorizationStatus: HMHomeManagerAuthorizationStatus = .determined
    @Published var errorMessage: String?

    private let homeKitManager: HomeKitManager
    let configService: DeviceConfigurationService
    private var cancellables = Set<AnyCancellable>()

    /// Debounces rapid refresh triggers to avoid redundant UI rebuilds.
    private var refreshWorkItem: DispatchWorkItem?

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var totalDeviceCount: Int {
        devicesByRoom.reduce(0) { $0 + $1.devices.count }
    }
    
    @Published var searchText = ""
    
    var filteredDevicesByRoom: [(roomName: String, devices: [DeviceModel])] {
        if searchText.isEmpty {
            return devicesByRoom
        }
        
        return devicesByRoom.compactMap { group in
            let filteredDevices = group.devices.filter { device in
                device.name.localizedCaseInsensitiveContains(searchText)
            }
            
            if filteredDevices.isEmpty {
                return nil
            }
            
            return (roomName: group.roomName, devices: filteredDevices)
        }
    }

    init(homeKitManager: HomeKitManager, configService: DeviceConfigurationService) {
        self.homeKitManager = homeKitManager
        self.configService = configService

        homeKitManager.$isReady
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReady in
                if isReady {
                    self?.refresh()
                }
            }
            .store(in: &cancellables)

        homeKitManager.$isReadingValues
            .receive(on: DispatchQueue.main)
            .assign(to: &$isReadingValues)

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
                self?.debouncedRefresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        devicesByRoom = homeKitManager.getDevicesGroupedByRoom()
        isLoading = false
    }

    /// Debounced version of refresh — coalesces multiple rapid triggers into one.
    private func debouncedRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refresh()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    func getConfig(deviceId: String, serviceId: String, characteristicId: String) async -> CharacteristicConfiguration {
        await configService.getConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId)
    }

    func setConfig(deviceId: String, serviceId: String, characteristicId: String, config: CharacteristicConfiguration) {
        Task {
            await configService.setConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId, config: config)
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }

    func setDeviceConfig(device: DeviceModel, mcpEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        let services = device.services.map { service in
            (serviceId: service.id, characteristicIds: service.characteristics.map(\.id))
        }
        Task {
            await configService.setAllForDevice(deviceId: device.id, services: services, mcpEnabled: mcpEnabled, webhookEnabled: webhookEnabled)
            await MainActor.run {
                objectWillChange.send()
            }
        }
    }

    func resetConfiguration() {
        Task {
            await configService.resetAll()
            await MainActor.run {
                objectWillChange.send()
            }
        }
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
