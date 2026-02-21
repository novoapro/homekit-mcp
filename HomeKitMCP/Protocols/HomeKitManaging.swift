import Foundation
import Combine

/// Protocol abstracting HomeKitManager for dependency injection and testability.
@MainActor
protocol HomeKitManaging: AnyObject {
    // MARK: - Published State
    var cachedDevices: [DeviceModel] { get }
    var isReady: Bool { get }
    var isReadingValues: Bool { get }

    // MARK: - Change Publishers
    var objectWillChange: ObservableObjectPublisher { get }

    /// Publishes every HomeKit state change. WorkflowEngine subscribes to this
    /// instead of being directly referenced — breaking the bidirectional coupling.
    var stateChangePublisher: PassthroughSubject<StateChange, Never> { get }

    // MARK: - Device Access
    func getAllDevices() -> [DeviceModel]
    func getDevicesGroupedByRoom() -> [(roomName: String, devices: [DeviceModel])]
    func getDeviceState(id: String) -> DeviceModel?

    // MARK: - Device Control
    func updateDevice(id: String, characteristicType: String, value: Any, serviceId: String?) async throws

    // MARK: - Configuration
    var configService: DeviceConfigurationService { get }
}
