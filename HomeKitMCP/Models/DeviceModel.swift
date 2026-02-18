import Foundation

struct DeviceModel: Identifiable, Codable {
    let id: String
    let name: String
    let roomName: String?
    let categoryType: String
    let services: [ServiceModel]
    var isReachable: Bool
}

struct ServiceModel: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let characteristics: [CharacteristicModel]

    /// Human-readable service type name (e.g. "Fan", "Lightbulb").
    var displayName: String {
        ServiceTypes.displayName(for: type)
    }
}

struct CharacteristicModel: Identifiable, Codable {
    let id: String
    let type: String
    var value: AnyCodable?
    let format: String
    let permissions: [String]
}

struct CharacteristicConfiguration: Codable, Equatable {
    var externalAccessEnabled: Bool
    var webhookEnabled: Bool

    static let `default` = CharacteristicConfiguration(externalAccessEnabled: true, webhookEnabled: false)
}
