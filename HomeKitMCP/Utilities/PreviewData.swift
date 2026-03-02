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
            isReachable: true,
            manufacturer: "Philips",
            model: "Hue White",
            serialNumber: "AA:BB:CC:DD:01",
            firmwareRevision: "1.50.2"
        ),
        DeviceModel(
            id: "device-2",
            name: "Bedroom Light",
            roomName: "Bedroom",
            categoryType: "HMAccessoryCategoryTypeLightbulb",
            services: [sampleService],
            isReachable: true,
            manufacturer: "Philips",
            model: "Hue White",
            serialNumber: "AA:BB:CC:DD:02",
            firmwareRevision: "1.50.2"
        ),
        DeviceModel(
            id: "device-3",
            name: "Front Door Lock",
            roomName: "Hallway",
            categoryType: "HMAccessoryCategoryTypeDoorLock",
            services: [],
            isReachable: false,
            manufacturer: "Yale",
            model: "Assure Lock",
            serialNumber: "YL-0001",
            firmwareRevision: "2.1.0"
        )
    ]

    static let devicesByRoom: [(roomName: String, devices: [DeviceModel])] = {
        let grouped = Dictionary(grouping: sampleDevices) { $0.roomName ?? "Default Room" }
        return grouped.map { (roomName: $0.key, devices: $0.value) }
            .sorted { $0.roomName < $1.roomName }
    }()

    // MARK: - Logs (All 8 StateChangeLog types)

    static let sampleLogs: [StateChangeLog] = [
        // 1. State Change
        .stateChange(
            deviceId: "device-1",
            deviceName: "Living Room Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        ),

        // 2. MCP Call
        .mcpCall(
            method: "tools/call",
            summary: "method: tools/call | tool: control_device | args: {device_id=device-1}",
            result: "Successfully set Power to true",
            detailedRequest: "{\"method\":\"tools/call\",\"params\":{\"name\":\"control_device\",\"arguments\":{\"device_id\":\"device-1\",\"value\":true}}}"
        ),

        // 3. REST Call
        .restCall(
            method: "GET /devices",
            summary: "GET /devices",
            result: "200 OK - 3 devices returned",
            detailedRequest: "Client: 192.168.1.100\nUser-Agent: curl/8.0\nContent-Type: -\nURL: GET /devices"
        ),

        // 4. Webhook Call
        .webhookCall(
            deviceId: "webhook-1",
            deviceName: "Living Room Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true),
            summary: "POST https://example.com/webhook - Power changed to ON",
            result: "HTTP 200 OK"
        ),

        // 5. Webhook Error
        .webhookError(
            deviceId: "webhook-error",
            deviceName: "Bedroom Light",
            serviceId: "service-1",
            serviceName: "Lightbulb",
            characteristicType: "00000025-0000-1000-8000-0026BB765291",
            oldValue: AnyCodable(true),
            newValue: AnyCodable(false),
            summary: "POST https://webhook.example.com/notify - Power changed",
            result: "Connection timeout after 30s",
            errorDetails: "Failed after 3 retries: Connection timeout"
        ),

        // 6. Server Error
        .serverError(errorDetails: "JSON parsing failed: Unexpected token in request body")
    ]

    // MARK: - Scenes

    static let sampleScenes: [SceneModel] = [
        SceneModel(
            id: "scene-1",
            name: "Good Morning",
            type: "Wake Up",
            isExecuting: false,
            actions: [
                SceneActionModel(id: "sa-1", deviceId: "device-1", deviceName: "Living Room Light", serviceName: "Lightbulb", characteristicType: "00000025-0000-1000-8000-0026BB765291", targetValue: AnyCodable(true)),
                SceneActionModel(id: "sa-2", deviceId: "device-2", deviceName: "Bedroom Light", serviceName: "Lightbulb", characteristicType: "00000008-0000-1000-8000-0026BB765291", targetValue: AnyCodable(80))
            ]
        ),
        SceneModel(
            id: "scene-2",
            name: "Good Night",
            type: "Sleep",
            isExecuting: false,
            actions: [
                SceneActionModel(id: "sa-3", deviceId: "device-1", deviceName: "Living Room Light", serviceName: "Lightbulb", characteristicType: "00000025-0000-1000-8000-0026BB765291", targetValue: AnyCodable(false)),
                SceneActionModel(id: "sa-4", deviceId: "device-3", deviceName: "Front Door Lock", serviceName: "Lock", characteristicType: "lock_state", targetValue: AnyCodable(true))
            ]
        ),
        SceneModel(
            id: "scene-3",
            name: "Movie Time",
            type: "Custom",
            isExecuting: true,
            actions: [
                SceneActionModel(id: "sa-5", deviceId: "device-1", deviceName: "Living Room Light", serviceName: "Lightbulb", characteristicType: "00000008-0000-1000-8000-0026BB765291", targetValue: AnyCodable(20))
            ]
        )
    ]

    // MARK: - Workflows

    static let sampleWorkflows: [Workflow] = [
        Workflow(
            name: "Evening Mode",
            description: "Dims lights and locks doors when sunset is detected",
            isEnabled: true,
            triggers: [
                .deviceStateChange(DeviceStateTrigger(
                    deviceId: "device-1",
                    characteristicId: "stable-char-power-1",
                    condition: .equals(AnyCodable(true)),
                    name: "Light turned on"
                ))
            ],
            blocks: [
                .action(.controlDevice(ControlDeviceAction(
                    deviceId: "device-2",
                    characteristicId: "stable-char-brightness-2",
                    value: AnyCodable(50),
                    name: "Dim bedroom to 50%"
                )), blockId: UUID()),
                .flowControl(.delay(DelayBlock(seconds: 5, name: "Wait 5 seconds")), blockId: UUID())
            ],
            metadata: WorkflowMetadata(
                createdBy: "user",
                tags: ["evening", "automation"],
                lastTriggeredAt: Date().addingTimeInterval(-3600),
                totalExecutions: 42,
                consecutiveFailures: 0
            )
        ),
        Workflow(
            name: "Security Check",
            description: "Locks the front door if left unlocked for 5 minutes",
            isEnabled: false,
            triggers: [
                .schedule(ScheduleTrigger(
                    scheduleType: .daily(time: ScheduleTime(hour: 22, minute: 0)),
                    name: "Every night at 10 PM"
                ))
            ],
            blocks: [
                .action(.controlDevice(ControlDeviceAction(
                    deviceId: "device-3",
                    characteristicId: "stable-char-lock-3",
                    value: AnyCodable(true),
                    name: "Lock front door"
                )), blockId: UUID())
            ],
            metadata: WorkflowMetadata(
                createdBy: "user",
                tags: ["security"],
                lastTriggeredAt: Date().addingTimeInterval(-86400),
                totalExecutions: 15,
                consecutiveFailures: 2
            )
        )
    ]

    // MARK: - AI Interaction Logs

    static let sampleAIInteractionLogs: [AIInteractionLog] = [
        AIInteractionLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-600),
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            operation: "generate",
            systemPrompt: "You are a HomeKit workflow generator...",
            userMessage: "Create a workflow that turns off all lights at midnight",
            rawResponse: "{\"name\": \"Midnight Lights Off\", ...}",
            parsedSuccessfully: true,
            errorMessage: nil,
            durationSeconds: 3.2
        ),
        AIInteractionLog(
            id: UUID(),
            timestamp: Date().addingTimeInterval(-1800),
            provider: "anthropic",
            model: "claude-sonnet-4-20250514",
            operation: "refine",
            systemPrompt: "You are a HomeKit workflow generator...",
            userMessage: "Add a condition to only run on weekdays",
            rawResponse: nil,
            parsedSuccessfully: false,
            errorMessage: "Rate limit exceeded",
            durationSeconds: 0.5
        )
    ]

    // MARK: - Draft Types (for editor previews)

    static let sampleTriggerDrafts: [TriggerDraft] = [
        {
            var draft = TriggerDraft(id: UUID())
            draft.deviceId = "device-1"
            draft.characteristicId = "00000025-0000-1000-8000-0026BB765291"
            draft.conditionType = .equals
            draft.conditionValue = "true"
            return draft
        }(),
        {
            var draft = TriggerDraft(id: UUID(), triggerType: .schedule)
            draft.scheduleType = .daily
            draft.scheduleHour = 22
            draft.scheduleMinute = 0
            return draft
        }()
    ]

    static let sampleBlockDrafts: [BlockDraft] = [
        {
            var d = ControlDeviceDraft()
            d.name = "Turn on light"
            d.deviceId = "device-1"
            d.characteristicId = "00000025-0000-1000-8000-0026BB765291"
            d.value = "true"
            return BlockDraft(id: UUID(), blockType: .controlDevice(d))
        }(),
        BlockDraft(id: UUID(), blockType: .delay(DelayDraft(seconds: 5.0))),
        BlockDraft(id: UUID(), blockType: .log(LogDraft(message: "Workflow step completed")))
    ]

    static let sampleConditionGroupDraft: ConditionGroupDraft = {
        var group = ConditionGroupDraft.empty()
        group.children = [
            .leaf(ConditionDraft(
                id: UUID(),
                conditionDraftType: .deviceState,
                deviceId: "device-1",
                serviceId: nil,
                characteristicId: "stable-char-power-1",
                comparisonType: .equals,
                comparisonValue: "true"
            )),
            .leaf({
                var d = ConditionDraft.emptyTimeCondition()
                d.timeConditionMode = .afterSunset
                return d
            }())
        ]
        return group
    }()

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
                serviceName: "Lightbulb",
                characteristicName: "Power",
                roomName: "Living Room",
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
                serviceName: "Lightbulb",
                characteristicName: "Power",
                roomName: "Bedroom",
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
                serviceName: "Lock Mechanism",
                characteristicName: "Lock State",
                roomName: "Hallway",
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
        let loggingService = LoggingService(storage: storage)
        let keychainService = KeychainService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, storage: storage)
        let registryService = DeviceRegistryService()
        let vm = HomeKitViewModel(homeKitManager: manager, registryService: registryService)
        vm.devicesByRoom = devicesByRoom
        vm.scenes = sampleScenes
        vm.filteredScenes = sampleScenes
        vm.isLoading = false
        return vm
    }

    static var logViewModel: LogViewModel {
        let storage = StorageService()
        let loggingService = LoggingService(storage: storage)
        let executionLogService = WorkflowExecutionLogService()

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
        let loggingService = LoggingService(storage: storage)
        let keychainService = KeychainService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, storage: storage)
        let workflowStorage = WorkflowStorageService()
        let workflowLogService = WorkflowExecutionLogService()
        let workflowEngine = WorkflowEngine(storageService: workflowStorage, homeKitManager: manager, loggingService: loggingService, executionLogService: workflowLogService, storage: storage)
        let mcpServer = MCPServer(
            homeKitManager: manager, loggingService: loggingService, storage: storage,
            workflowStorageService: workflowStorage, workflowEngine: workflowEngine, workflowExecutionLogService: workflowLogService,
            keychainService: keychainService
        )
        let aiInteractionLogService = AIInteractionLogService()
        let aiWorkflowService = AIWorkflowService(storage: storage, homeKitManager: manager, keychainService: keychainService, interactionLog: aiInteractionLogService)
        let registryService = DeviceRegistryService()
        let backupService = BackupService(storage: storage, keychainService: keychainService, workflowStorageService: workflowStorage, homeKitManager: manager, loggingService: loggingService, deviceRegistryService: registryService)
        let cloudBackupService = CloudBackupService(backupService: backupService, storage: storage, workflowStorageService: workflowStorage)
        let appleSignInService = AppleSignInService(keychainService: keychainService)
        return SettingsViewModel(
            storage: storage, webhookService: webhookService, mcpServer: mcpServer,
            keychainService: keychainService, aiWorkflowService: aiWorkflowService,
            backupService: backupService, cloudBackupService: cloudBackupService, appleSignInService: appleSignInService,
            deviceRegistryService: registryService, homeKitManager: manager,
            workflowStorageService: workflowStorage
        )
    }

    static var workflowViewModel: WorkflowViewModel {
        let storage = StorageService()
        let loggingService = LoggingService(storage: storage)
        let keychainService = KeychainService()
        let workflowStorage = WorkflowStorageService()
        let workflowLogService = WorkflowExecutionLogService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, storage: storage)
        let engine = WorkflowEngine(
            storageService: workflowStorage,
            homeKitManager: manager,
            loggingService: loggingService,
            executionLogService: workflowLogService,
            storage: storage
        )
        let vm = WorkflowViewModel(storageService: workflowStorage, executionLogService: workflowLogService, workflowEngine: engine, homeKitManager: manager)
        vm.workflows = sampleWorkflows
        vm.executionLogs = sampleWorkflowLogs
        return vm
    }

    // MARK: - Service Helpers (for views needing raw services)

    static var previewStorage: StorageService { StorageService() }

    static var previewHomeKitManager: HomeKitManager {
        let storage = StorageService()
        let loggingService = LoggingService(storage: storage)
        let keychainService = KeychainService()
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        return HomeKitManager(loggingService: loggingService, webhookService: webhookService, storage: storage)
    }

    static var previewAIWorkflowService: AIWorkflowService {
        let storage = StorageService()
        let keychainService = KeychainService()
        let manager = previewHomeKitManager
        let interactionLog = AIInteractionLogService()
        return AIWorkflowService(storage: storage, homeKitManager: manager, keychainService: keychainService, interactionLog: interactionLog)
    }

    static var previewCloudBackupService: CloudBackupService {
        let storage = StorageService()
        let keychainService = KeychainService()
        let loggingService = LoggingService(storage: storage)
        let webhookService = WebhookService(storage: storage, loggingService: loggingService, keychainService: keychainService)
        let manager = HomeKitManager(loggingService: loggingService, webhookService: webhookService, storage: storage)
        let workflowStorage = WorkflowStorageService()
        let backupService = BackupService(storage: storage, keychainService: keychainService, workflowStorageService: workflowStorage, homeKitManager: manager, loggingService: loggingService, deviceRegistryService: DeviceRegistryService())
        return CloudBackupService(backupService: backupService, storage: storage, workflowStorageService: workflowStorage)
    }

    static var previewWorkflowStorageService: WorkflowStorageService {
        WorkflowStorageService()
    }
}
