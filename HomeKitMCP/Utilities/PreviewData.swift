import Foundation

@MainActor
enum PreviewData {
    // MARK: - Devices

    static let sampleCharacteristics = [
        CharacteristicModel(
            id: "char-1",
            type: "00000025-0000-1000-8000-0026BB765291",
            value: AnyCodable(true),
            format: "bool",
            permissions: ["read", "write"]
        ),
        CharacteristicModel(
            id: "char-2",
            type: "00000008-0000-1000-8000-0026BB765291",
            value: AnyCodable(75),
            format: "int",
            permissions: ["read", "write"]
        )
    ]

    static let sampleService = ServiceModel(
        id: "service-1",
        name: "Lightbulb",
        type: "00000043-0000-1000-8000-0026BB765291",
        characteristics: sampleCharacteristics
    )

    static let sampleDevices: [DeviceModel] = [
        DeviceModel(
            id: "device-1",
            name: "Living Room Light",
            roomName: "Living Room",
            categoryType: "HMAccessoryCategoryTypeLightbulb",
            services: [sampleService],
            isReachable: true
        ),
        DeviceModel(
            id: "device-2",
            name: "Bedroom Light",
            roomName: "Bedroom",
            categoryType: "HMAccessoryCategoryTypeLightbulb",
            services: [sampleService],
            isReachable: true
        ),
        DeviceModel(
            id: "device-3",
            name: "Front Door Lock",
            roomName: "Hallway",
            categoryType: "HMAccessoryCategoryTypeLock",
            services: [],
            isReachable: false
        )
    ]

    static let devicesByRoom: [(roomName: String, devices: [DeviceModel])] = {
        let grouped = Dictionary(grouping: sampleDevices) { $0.roomName ?? "Default Room" }
        return grouped.map { (roomName: $0.key, devices: $0.value) }
            .sorted { $0.roomName < $1.roomName }
    }()

    // MARK: - Logs

    static let sampleLogs: [StateChangeLog] = [
        StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            deviceId: "device-1",
            deviceName: "Living Room Light",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        ),
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-3600),
            deviceId: "device-2",
            deviceName: "Bedroom Light",
            characteristicType: "00000008-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(100),
            newValue: AnyCodable(50)
        ),
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-86400),
            deviceId: "device-3",
            deviceName: "Front Door Lock",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: nil,
            newValue: AnyCodable(true)
        )
    ]

    // MARK: - ViewModels

    static var homeKitViewModel: HomeKitViewModel {
        let storage = StorageService()
        let loggingService = LoggingService()
        let configService = DeviceConfigurationService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storage)
        let vm = HomeKitViewModel(homeKitManager: manager, configService: configService)
        vm.devicesByRoom = devicesByRoom
        vm.isLoading = false
        return vm
    }

    static var logViewModel: LogViewModel {
        let loggingService = LoggingService()
        let vm = LogViewModel(loggingService: loggingService)
        
        // Manually set published properties for preview
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let grouped = Dictionary(grouping: sampleLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }
        
        vm.groupedLogs = grouped
            .sorted { $0.key > $1.key }
            .map { (date, logs) in
                let label: String
                if calendar.isDateInToday(date) {
                    label = "Today"
                } else if calendar.isDateInYesterday(date) {
                    label = "Yesterday"
                } else {
                    label = formatter.string(from: date)
                }
                return (date: date.ISO8601Format(), label: label, logs: logs)
            }
            
        vm.filteredLogCount = sampleLogs.count
        return vm
    }

    static var settingsViewModel: SettingsViewModel {
        let storage = StorageService()
        let loggingService = LoggingService()
        let configService = DeviceConfigurationService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storage)
        let mcpServer = MCPServer(homeKitManager: manager, loggingService: loggingService, configService: configService)
        return SettingsViewModel(storage: storage, webhookService: webhookService, mcpServer: mcpServer, configService: configService)
    }
}
