import Foundation

enum LogCategory: String, Codable {
    case stateChange = "state_change"
    case webhookError = "webhook_error"
    case webhookCall = "webhook_call"
    case serverError = "server_error"
    case mcpCall = "mcp_call"
    case restCall = "rest_call"
    case workflowExecution = "workflow_execution"
    case workflowError = "workflow_error"
}

struct StateChangeLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let deviceId: String
    let deviceName: String
    let serviceId: String?
    let serviceName: String?
    let characteristicType: String
    let oldValue: AnyCodable?
    let newValue: AnyCodable?
    var category: LogCategory
    var errorDetails: String?
    var requestBody: String?
    var responseBody: String?
    var detailedRequestBody: String?
    var detailedResponseBody: String?

    init(id: UUID, timestamp: Date, deviceId: String, deviceName: String, serviceId: String? = nil, serviceName: String? = nil, characteristicType: String, oldValue: AnyCodable?, newValue: AnyCodable?, category: LogCategory = .stateChange, errorDetails: String? = nil, requestBody: String? = nil, responseBody: String? = nil, detailedRequestBody: String? = nil, detailedResponseBody: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.oldValue = oldValue
        self.newValue = newValue
        self.category = category
        self.errorDetails = errorDetails
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.detailedRequestBody = detailedRequestBody
        self.detailedResponseBody = detailedResponseBody
    }
}

struct StateChange {
    let deviceId: String
    let deviceName: String
    let serviceId: String?
    let serviceName: String?
    let characteristicType: String
    let oldValue: Any?
    let newValue: Any?
    let timestamp: Date

    init(deviceId: String, deviceName: String, serviceId: String? = nil, serviceName: String? = nil, characteristicType: String, oldValue: Any? = nil, newValue: Any? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.serviceId = serviceId
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}
