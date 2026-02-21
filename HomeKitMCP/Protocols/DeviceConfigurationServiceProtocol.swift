import Foundation

/// Protocol abstracting DeviceConfigurationService for dependency injection and testability.
protocol DeviceConfigurationServiceProtocol: AnyObject, Sendable {
    func getConfig(deviceId: String, serviceId: String, characteristicId: String) async -> CharacteristicConfiguration
    func setConfig(deviceId: String, serviceId: String, characteristicId: String, config: CharacteristicConfiguration) async
    func isExternalAccessEnabled(deviceId: String, serviceId: String, characteristicId: String) async -> Bool
    func isWebhookEnabled(deviceId: String, serviceId: String, characteristicId: String) async -> Bool
    func setAllForDevice(deviceId: String, services: [(serviceId: String, characteristicIds: [String])], externalAccessEnabled: Bool?, webhookEnabled: Bool?) async
    func getAllConfigs() async -> [String: CharacteristicConfiguration]
    func resetAll() async
    func replaceAll(configs: [String: CharacteristicConfiguration]) async
}
