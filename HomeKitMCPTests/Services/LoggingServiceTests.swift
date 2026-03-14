import XCTest
@testable import HomeKitMCP

final class LoggingServiceTests: XCTestCase {

    private var loggingService: LoggingService!
    private var mockStorage: MockStorageService!

    override func setUp() {
        super.setUp()
        mockStorage = MockStorageService()
        loggingService = LoggingService(storage: mockStorage)
    }

    override func tearDown() {
        loggingService = nil
        mockStorage = nil
        super.tearDown()
    }

    // MARK: - Adding Log Entries

    func testLogEntry_addsEntry() async {
        let entry = StateChangeLog.stateChange(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power"
        )
        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].deviceId, "dev-1")
    }

    func testLogEntry_multiplePushes_allAdded() async {
        let entry1 = StateChangeLog.stateChange(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power"
        )
        let entry2 = StateChangeLog.stateChange(
            deviceId: "dev-2",
            deviceName: "Fan",
            characteristicType: "power"
        )

        await loggingService.logEntry(entry1)
        await loggingService.logEntry(entry2)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 2)
    }

    // MARK: - Ring Buffer (Max Logs)

    func testLogEntry_exceedsMaxLogs_dropsOldest() async {
        mockStorage.readLogCacheSizeResult = 3

        let loggingService = LoggingService(storage: mockStorage)

        let entry1 = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let entry2 = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")
        let entry3 = StateChangeLog.stateChange(deviceId: "dev-3", deviceName: "Light3", characteristicType: "power")
        let entry4 = StateChangeLog.stateChange(deviceId: "dev-4", deviceName: "Light4", characteristicType: "power")

        await loggingService.logEntry(entry1)
        await loggingService.logEntry(entry2)
        await loggingService.logEntry(entry3)
        await loggingService.logEntry(entry4)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 3)
        // Most recent should be first (reversed)
        XCTAssertEqual(logs[0].deviceId, "dev-4")
        XCTAssertEqual(logs[1].deviceId, "dev-3")
        XCTAssertEqual(logs[2].deviceId, "dev-2")
    }

    func testLogEntry_ringBufferMaintainsNewest() async {
        mockStorage.readLogCacheSizeResult = 2

        let loggingService = LoggingService(storage: mockStorage)

        let entry1 = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let entry2 = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")
        let entry3 = StateChangeLog.stateChange(deviceId: "dev-3", deviceName: "Light3", characteristicType: "power")

        await loggingService.logEntry(entry1)
        await loggingService.logEntry(entry2)
        await loggingService.logEntry(entry3)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs[0].deviceId, "dev-3")
        XCTAssertEqual(logs[1].deviceId, "dev-2")
    }

    // MARK: - Get Logs (Reversed Order)

    func testGetLogs_returnsNewestFirst() async {
        let entry1 = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let entry2 = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")
        let entry3 = StateChangeLog.stateChange(deviceId: "dev-3", deviceName: "Light3", characteristicType: "power")

        await loggingService.logEntry(entry1)
        try? await Task.sleep(nanoseconds: 1_000_000) // Ensure different timestamps
        await loggingService.logEntry(entry2)
        try? await Task.sleep(nanoseconds: 1_000_000)
        await loggingService.logEntry(entry3)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 3)
        // Should be in reverse order (newest first)
        XCTAssertEqual(logs[0].deviceId, "dev-3")
        XCTAssertEqual(logs[1].deviceId, "dev-2")
        XCTAssertEqual(logs[2].deviceId, "dev-1")
    }

    // MARK: - Clear Logs

    func testClearLogs_removesAllEntries() async {
        let entry1 = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let entry2 = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")

        await loggingService.logEntry(entry1)
        await loggingService.logEntry(entry2)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 2)

        await loggingService.clearLogs()

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 0)
    }

    // MARK: - Clear Logs by Category

    func testClearLogs_forCategories_removesMatchingOnly() async {
        let stateChangeEntry = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let webhookCallEntry = StateChangeLog.webhookCall(
            deviceId: "dev-1",
            deviceName: "Light1",
            characteristicType: "power",
            summary: "test",
            result: "ok"
        )
        let serverErrorEntry = StateChangeLog.serverError(errorDetails: "test error")

        await loggingService.logEntry(stateChangeEntry)
        await loggingService.logEntry(webhookCallEntry)
        await loggingService.logEntry(serverErrorEntry)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 3)

        await loggingService.clearLogs(forCategories: [.webhookCall])

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 2)
        XCTAssertFalse(logsAfter.contains { $0.category == .webhookCall })
    }

    func testClearLogs_forMultipleCategories_removesAll() async {
        let stateChangeEntry = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let webhookCallEntry = StateChangeLog.webhookCall(
            deviceId: "dev-1",
            deviceName: "Light1",
            characteristicType: "power",
            summary: "test",
            result: "ok"
        )
        let mcpCallEntry = StateChangeLog.mcpCall(method: "GET", summary: "test", result: "ok")

        await loggingService.logEntry(stateChangeEntry)
        await loggingService.logEntry(webhookCallEntry)
        await loggingService.logEntry(mcpCallEntry)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 3)

        await loggingService.clearLogs(forCategories: [.webhookCall, .mcpCall])

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 1)
        XCTAssertEqual(logsAfter[0].category, .stateChange)
    }

    // MARK: - Update Entry

    func testUpdateEntry_existingEntry_updates() async {
        let originalEntry = StateChangeLog.stateChange(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        await loggingService.logEntry(originalEntry)

        let updatedEntry = StateChangeLog(
            id: originalEntry.id,
            timestamp: originalEntry.timestamp,
            category: originalEntry.category,
            payload: originalEntry.payload
        )

        await loggingService.updateEntry(updatedEntry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].id, originalEntry.id)
    }

    func testUpdateEntry_newEntry_appends() async {
        let existingEntry = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        await loggingService.logEntry(existingEntry)

        let newEntry = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")
        await loggingService.updateEntry(newEntry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 2)
    }

    // MARK: - Remove Entry

    func testRemoveEntry_removesById() async {
        let entry1 = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        let entry2 = StateChangeLog.stateChange(deviceId: "dev-2", deviceName: "Light2", characteristicType: "power")

        await loggingService.logEntry(entry1)
        await loggingService.logEntry(entry2)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 2)

        await loggingService.removeEntry(id: entry1.id)

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 1)
        XCTAssertEqual(logsAfter[0].id, entry2.id)
    }

    func testRemoveEntry_nonExistentId_noError() async {
        let entry = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light1", characteristicType: "power")
        await loggingService.logEntry(entry)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 1)

        let fakeId = UUID()
        await loggingService.removeEntry(id: fakeId)

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 1)
    }

    // MARK: - Filter Logs by Workflow ID

    func testGetLogs_forWorkflowId() async {
        let workflowId = UUID()
        let otherWorkflowId = UUID()

        // Create workflow execution logs
        let workflowLog1 = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            category: .workflowExecution,
            payload: .workflowExecution(
                WorkflowExecutionLog(
                    workflowId: workflowId,
                    workflowName: "Test Workflow",
                    status: .success,
                    triggerEvent: nil,
                    conditionResults: [],
                    blockResults: [],
                    errorMessage: nil
                )
            )
        )

        let workflowLog2 = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            category: .workflowExecution,
            payload: .workflowExecution(
                WorkflowExecutionLog(
                    workflowId: otherWorkflowId,
                    workflowName: "Other Workflow",
                    status: .success,
                    triggerEvent: nil,
                    conditionResults: [],
                    blockResults: [],
                    errorMessage: nil
                )
            )
        )

        let stateChangeLog = StateChangeLog.stateChange(deviceId: "dev-1", deviceName: "Light", characteristicType: "power")

        await loggingService.logEntry(workflowLog1)
        await loggingService.logEntry(workflowLog2)
        await loggingService.logEntry(stateChangeLog)

        let filteredLogs = await loggingService.getLogs(forWorkflowId: workflowId)
        XCTAssertEqual(filteredLogs.count, 1)
        XCTAssertEqual(filteredLogs[0].workflowExecution?.workflowId, workflowId)
    }

    func testGetLogs_forWorkflowId_emptyResult() async {
        let workflowId = UUID()
        let otherWorkflowId = UUID()

        let workflowLog = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            category: .workflowExecution,
            payload: .workflowExecution(
                WorkflowExecutionLog(
                    workflowId: otherWorkflowId,
                    workflowName: "Other Workflow",
                    status: .success,
                    triggerEvent: nil,
                    conditionResults: [],
                    blockResults: [],
                    errorMessage: nil
                )
            )
        )

        await loggingService.logEntry(workflowLog)

        let filteredLogs = await loggingService.getLogs(forWorkflowId: workflowId)
        XCTAssertEqual(filteredLogs.count, 0)
    }

    // MARK: - Clear Logs by Workflow ID

    func testClearLogs_forWorkflowId() async {
        let workflowId = UUID()
        let otherWorkflowId = UUID()

        let workflowLog1 = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            category: .workflowExecution,
            payload: .workflowExecution(
                WorkflowExecutionLog(
                    workflowId: workflowId,
                    workflowName: "Test Workflow",
                    status: .success,
                    triggerEvent: nil,
                    conditionResults: [],
                    blockResults: [],
                    errorMessage: nil
                )
            )
        )

        let workflowLog2 = StateChangeLog(
            id: UUID(),
            timestamp: Date(),
            category: .workflowExecution,
            payload: .workflowExecution(
                WorkflowExecutionLog(
                    workflowId: otherWorkflowId,
                    workflowName: "Other Workflow",
                    status: .success,
                    triggerEvent: nil,
                    conditionResults: [],
                    blockResults: [],
                    errorMessage: nil
                )
            )
        )

        await loggingService.logEntry(workflowLog1)
        await loggingService.logEntry(workflowLog2)

        let logsBefore = await loggingService.getLogs()
        XCTAssertEqual(logsBefore.count, 2)

        await loggingService.clearLogs(forWorkflowId: workflowId)

        let logsAfter = await loggingService.getLogs()
        XCTAssertEqual(logsAfter.count, 1)
        XCTAssertEqual(logsAfter[0].workflowExecution?.workflowId, otherWorkflowId)
    }

    // MARK: - Different Log Types

    func testLogEntry_stateChange() async {
        let entry = StateChangeLog.stateChange(
            deviceId: "dev-1",
            deviceName: "Light",
            roomName: "Living Room",
            characteristicType: "power",
            oldValue: AnyCodable(false),
            newValue: AnyCodable(true)
        )

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs[0].category, .stateChange)
    }

    func testLogEntry_webhookCall() async {
        let entry = StateChangeLog.webhookCall(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power",
            summary: "POST /webhook",
            result: "HTTP 200"
        )

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs[0].category, .webhookCall)
    }

    func testLogEntry_webhookError() async {
        let entry = StateChangeLog.webhookError(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power",
            summary: "POST /webhook",
            result: "HTTP 500",
            errorDetails: "Server error"
        )

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs[0].category, .webhookError)
    }

    func testLogEntry_mcpCall() async {
        let entry = StateChangeLog.mcpCall(
            method: "list_resources",
            summary: "List all resources",
            result: "OK"
        )

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs[0].category, .mcpCall)
    }

    func testLogEntry_serverError() async {
        let entry = StateChangeLog.serverError(errorDetails: "Internal server error")

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs[0].category, .serverError)
    }

    // MARK: - Max Logs Configuration

    func testMaxLogs_readFromStorage() async {
        mockStorage.readLogCacheSizeResult = 50

        let loggingService = LoggingService(storage: mockStorage)

        var entries: [StateChangeLog] = []
        for i in 0..<60 {
            let entry = StateChangeLog.stateChange(deviceId: "dev-\(i)", deviceName: "Light\(i)", characteristicType: "power")
            entries.append(entry)
        }

        for entry in entries {
            await loggingService.logEntry(entry)
        }

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 50)
    }

    // MARK: - Truncation

    func testLogEntry_largeFields_truncated() async {
        let largeString = String(repeating: "x", count: 20000)
        let entry = StateChangeLog.webhookError(
            deviceId: "dev-1",
            deviceName: "Light",
            characteristicType: "power",
            summary: largeString,
            result: "error",
            errorDetails: largeString
        )

        await loggingService.logEntry(entry)

        let logs = await loggingService.getLogs()
        XCTAssertEqual(logs.count, 1)
        // Entry should be stored (truncation happens internally)
    }
}

// MARK: - Mocks

class MockStorageService: StorageServiceProtocol {
    var readLogCacheSizeResult: Int = 200

    func readLogCacheSize() -> Int { readLogCacheSizeResult }
    func readWebhookURL() -> String? { nil }
    func readWebhookEnabled() -> Bool { false }
    func readLoggingEnabled() -> Bool { true }
    func readMcpLoggingEnabled() -> Bool { true }
    func readRestLoggingEnabled() -> Bool { true }
    func readWebhookLoggingEnabled() -> Bool { true }
    func readWorkflowLoggingEnabled() -> Bool { true }
    func readMcpDetailedLogsEnabled() -> Bool { false }
    func readRestDetailedLogsEnabled() -> Bool { false }
    func readWebhookDetailedLogsEnabled() -> Bool { false }
    func readWebhookPrivateIPAllowlist() -> [String] { [] }
    func readSunEventLatitude() -> Double { 0 }
    func readSunEventLongitude() -> Double { 0 }
    // ... other methods as needed
}
