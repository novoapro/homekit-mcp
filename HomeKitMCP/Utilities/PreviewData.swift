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
            units: nil,
            permissions: ["read", "write"],
            minValue: nil,
            maxValue: nil,
            stepValue: nil,
            validValues: nil
        ),
        CharacteristicModel(
            id: "char-2",
            type: "00000008-0000-1000-8000-0026BB765291",
            value: AnyCodable(75),
            format: "int",
            units: "%",
            permissions: ["read", "write"],
            minValue: 0,
            maxValue: 100,
            stepValue: 1,
            validValues: nil
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
            categoryType: "HMAccessoryCategoryTypeDoorLock",
            services: [],
            isReachable: false
        )
    ]

    static let devicesByRoom: [(roomName: String, devices: [DeviceModel])] = {
        let grouped = Dictionary(grouping: sampleDevices) { $0.roomName ?? "Default Room" }
        return grouped.map { (roomName: $0.key, devices: $0.value) }
            .sorted { $0.roomName < $1.roomName }
    }()

    // MARK: - Logs (All 8 StateChangeLog types)

    static let sampleLogs: [StateChangeLog] = [
        // 1. State Change: Device characteristic changed
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-20),
            deviceId: "device-1",
            deviceName: "Living Room Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        ),

        // 2. MCP Call: Tool invocation (successful)
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-80),
            deviceId: "mcp",
            deviceName: "MCP Server",
            characteristicType: "tools/call",
            oldValue: nil,
            newValue: nil,
            category: .mcpCall,
            requestBody: "method: tools/call | tool: control_device | args: {device_id=device-1}",
            responseBody: "✓ Successfully set Power to true",
            detailedRequestBody: "{\"method\":\"tools/call\",\"params\":{\"name\":\"control_device\",\"arguments\":{\"device_id\":\"device-1\",\"value\":true}}}",
            detailedResponseBody: "{\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Successfully set Power to true on device-1\"}],\"isError\":false}}"
        ),

        // 3. REST API: GET request (successful)
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-140),
            deviceId: "rest",
            deviceName: "REST API",
            characteristicType: "GET /devices",
            oldValue: nil,
            newValue: nil,
            category: .restCall,
            requestBody: "GET /devices",
            responseBody: "200 OK - 3 devices returned",
            detailedResponseBody: "[{\"id\":\"device-1\",\"name\":\"Living Room Light\",\"status\":\"on\",\"brightness\":75}]"
        ),

        // 4. Webhook Call: External service notification (successful)
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-200),
            deviceId: "webhook-1",
            deviceName: "Living Room Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true),
            category: .webhookCall,
            requestBody: "POST https://example.com/webhook - Power changed to ON",
            responseBody: "HTTP 200 OK"
        ),

        // 5. Webhook Error: Failed to send to external service
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-320),
            deviceId: "webhook-error",
            deviceName: "Bedroom Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(true),
            newValue: AnyCodable(false),
            category: .webhookError,
            errorDetails: "Failed after 3 retries: Connection timeout",
            requestBody: "POST https://webhook.example.com/notify - Power changed",
            responseBody: "⚠ Connection timeout after 30s"
        ),

        // 6. Server Error: MCP server internal error
        StateChangeLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-420),
            deviceId: "server",
            deviceName: "MCP Server",
            characteristicType: "server",
            oldValue: nil,
            newValue: nil,
            category: .serverError,
            errorDetails: "JSON parsing failed: Unexpected token in request body"
        )
    ]

    // MARK: - Workflow Logs

    static let sampleWorkflowLogs: [WorkflowExecutionLog] = [
        // Running workflow: in progress with elapsed time
        WorkflowExecutionLog(
            id: UUID(),
            workflowId: UUID(),
            workflowName: "Evening Mode",
            triggeredAt: Date().addingTimeInterval(-35),
            completedAt: nil,
            triggerEvent: TriggerEvent(
                deviceId: "device-1",
                deviceName: "Living Room Light",
                serviceId: "service-1",
                characteristicType: "power",
                oldValue: AnyCodable(false),
                newValue: AnyCodable(true),
                triggerDescription: "Power turned on"
            ),
            conditionResults: nil,
            blockResults: [
                BlockResult(
                    blockIndex: 0,
                    blockKind: "action",
                    blockType: "control_device",
                    blockName: "Dim lights to 50%",
                    status: .running,
                    startedAt: Date().addingTimeInterval(-32),
                    completedAt: nil,
                    detail: nil,
                    errorMessage: nil,
                    nestedResults: nil
                ),
                BlockResult(
                    blockIndex: 1,
                    blockKind: "action",
                    blockType: "control_device",
                    blockName: "Close blinds",
                    status: .running,
                    startedAt: Date().addingTimeInterval(-10),
                    completedAt: nil,
                    detail: nil,
                    errorMessage: nil,
                    nestedResults: nil
                )
            ],
            status: .running,
            errorMessage: nil
        ),
        // Successful workflow: completed quickly
        WorkflowExecutionLog(
            id: UUID(),
            workflowId: UUID(),
            workflowName: "Turn Off Lights",
            triggeredAt: Date().addingTimeInterval(-150),
            completedAt: Date().addingTimeInterval(-145),
            triggerEvent: TriggerEvent(
                deviceId: "device-2",
                deviceName: "Bedroom Light",
                serviceId: "service-1",
                characteristicType: "power",
                oldValue: AnyCodable(true),
                newValue: AnyCodable(false),
                triggerDescription: "Power turned off"
            ),
            conditionResults: nil,
            blockResults: [
                BlockResult(
                    blockIndex: 0,
                    blockKind: "condition",
                    blockType: "time_range",
                    blockName: "Is night time?",
                    status: .success,
                    startedAt: Date().addingTimeInterval(-149),
                    completedAt: Date().addingTimeInterval(-148),
                    detail: nil,
                    errorMessage: nil,
                    nestedResults: nil
                ),
                BlockResult(
                    blockIndex: 1,
                    blockKind: "action",
                    blockType: "send_notification",
                    blockName: "Send push notification",
                    status: .success,
                    startedAt: Date().addingTimeInterval(-147),
                    completedAt: Date().addingTimeInterval(-145),
                    detail: nil,
                    errorMessage: nil,
                    nestedResults: nil
                )
            ],
            status: .success,
            errorMessage: nil
        ),
        // Failed workflow: shows error state
        WorkflowExecutionLog(
            id: UUID(),
            workflowId: UUID(),
            workflowName: "Security Alert",
            triggeredAt: Date().addingTimeInterval(-300),
            completedAt: Date().addingTimeInterval(-295),
            triggerEvent: TriggerEvent(
                deviceId: "device-3",
                deviceName: "Front Door Lock",
                serviceId: "service-2",
                characteristicType: "lock_state",
                oldValue: AnyCodable(false),
                newValue: AnyCodable(true),
                triggerDescription: "Door locked"
            ),
            conditionResults: nil,
            blockResults: [
                BlockResult(
                    blockIndex: 0,
                    blockKind: "action",
                    blockType: "send_notification",
                    blockName: "Send security alert",
                    status: .failure,
                    startedAt: Date().addingTimeInterval(-298),
                    completedAt: Date().addingTimeInterval(-295),
                    detail: nil,
                    errorMessage: "Notification service offline",
                    nestedResults: nil
                )
            ],
            status: .failure,
            errorMessage: "Failed to send security notification"
        )
    ]

    // MARK: - ViewModels

    static var homeKitViewModel: HomeKitViewModel {
        let storage = StorageService()
        let loggingService = LoggingService()
        let configService = DeviceConfigurationService()
        let keychainService = KeychainService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storage)
        let vm = HomeKitViewModel(homeKitManager: manager, configService: configService)
        vm.devicesByRoom = devicesByRoom
        vm.isLoading = false
        return vm
    }

    static var logViewModel: LogViewModel {
        let loggingService = LoggingService()
        let executionLogService = WorkflowExecutionLogService()
        let storage = StorageService()

        let vm = LogViewModel(loggingService: loggingService, executionLogService: executionLogService, storage: storage)

        // For preview, manually populate groupedLogs with sample data
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        // Convert to UnifiedLog format: combine state change logs and workflow execution logs
        var unifiedLogs: [UnifiedLog] = sampleLogs.map { .stateChange($0) }
        unifiedLogs.append(contentsOf: sampleWorkflowLogs.map { .workflowExecution($0) })

        // Sort by timestamp descending (newest first)
        unifiedLogs.sort { $0.timestamp > $1.timestamp }

        let grouped = Dictionary(grouping: unifiedLogs) { log in
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
                // Sort logs within each group by timestamp descending
                let sortedLogs = logs.sorted { $0.timestamp > $1.timestamp }
                return (date: date.ISO8601Format(), label: label, logs: sortedLogs)
            }

        vm.filteredLogCount = unifiedLogs.count
        return vm
    }

    static var settingsViewModel: SettingsViewModel {
        let storage = StorageService()
        let loggingService = LoggingService()
        let configService = DeviceConfigurationService()
        let keychainService = KeychainService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storage)
        let workflowStorage = WorkflowStorageService()
        let workflowLogService = WorkflowExecutionLogService()
        let workflowEngine = WorkflowEngine(storageService: workflowStorage, homeKitManager: manager, loggingService: loggingService, executionLogService: workflowLogService, storage: storage)
        let mcpServer = MCPServer(
            homeKitManager: manager, loggingService: loggingService, configService: configService, storage: storage,
            workflowStorageService: workflowStorage, workflowEngine: workflowEngine, workflowExecutionLogService: workflowLogService,
            keychainService: keychainService
        )
        let aiInteractionLogService = AIInteractionLogService()
        let aiWorkflowService = AIWorkflowService(storage: storage, homeKitManager: manager, keychainService: keychainService, interactionLog: aiInteractionLogService)
        let backupService = BackupService(storage: storage, keychainService: keychainService, configService: configService, workflowStorageService: workflowStorage)
        let cloudBackupService = CloudBackupService(backupService: backupService, storage: storage, workflowStorageService: workflowStorage)
        let appleSignInService = AppleSignInService(keychainService: keychainService)
        return SettingsViewModel(
            storage: storage, webhookService: webhookService, mcpServer: mcpServer, configService: configService,
            keychainService: keychainService, aiWorkflowService: aiWorkflowService,
            backupService: backupService, cloudBackupService: cloudBackupService, appleSignInService: appleSignInService
        )
    }

    static var workflowViewModel: WorkflowViewModel {
        let storage = StorageService()
        let loggingService = LoggingService()
        let configService = DeviceConfigurationService()
        let keychainService = KeychainService()
        let workflowStorage = WorkflowStorageService()
        let workflowLogService = WorkflowExecutionLogService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, configService: configService, storage: storage)
        let engine = WorkflowEngine(
            storageService: workflowStorage,
            homeKitManager: manager,
            loggingService: loggingService,
            executionLogService: workflowLogService,
            storage: storage
        )
        return WorkflowViewModel(storageService: workflowStorage, executionLogService: workflowLogService, workflowEngine: engine, homeKitManager: manager)
    }
}
