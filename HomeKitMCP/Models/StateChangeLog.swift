import Foundation

struct StateChangeLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let deviceId: String
    let deviceName: String
    let characteristicType: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
}

struct StateChange {
    let deviceId: String
    let deviceName: String
    let characteristicType: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date

    init(deviceId: String, deviceName: String, characteristicType: String, oldValue: Any? = nil, newValue: Any? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.characteristicType = characteristicType
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}
