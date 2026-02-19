import Foundation

actor DeviceConfigurationService {
    private var configs: [String: CharacteristicConfiguration] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = appSupport.appendingPathComponent("HomeKitMCP")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("device-config.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: CharacteristicConfiguration].self, from: data) {
            self.configs = saved
        }
    }

    private static func key(deviceId: String, serviceId: String, characteristicId: String) -> String {
        "\(deviceId):\(serviceId):\(characteristicId)"
    }

    func getConfig(deviceId: String, serviceId: String, characteristicId: String) -> CharacteristicConfiguration {
        let k = Self.key(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId)
        return configs[k] ?? .default
    }

    func setConfig(deviceId: String, serviceId: String, characteristicId: String, config: CharacteristicConfiguration) {
        let k = Self.key(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId)
        if config == .default {
            configs.removeValue(forKey: k)
        } else {
            configs[k] = config
        }
        debouncedSave()
    }

    func isExternalAccessEnabled(deviceId: String, serviceId: String, characteristicId: String) -> Bool {
        getConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId).externalAccessEnabled
    }

    func isWebhookEnabled(deviceId: String, serviceId: String, characteristicId: String) -> Bool {
        getConfig(deviceId: deviceId, serviceId: serviceId, characteristicId: characteristicId).webhookEnabled
    }

    func setAllForDevice(deviceId: String, services: [(serviceId: String, characteristicIds: [String])], externalAccessEnabled: Bool? = nil, webhookEnabled: Bool? = nil) {
        for service in services {
            for charId in service.characteristicIds {
                let k = Self.key(deviceId: deviceId, serviceId: service.serviceId, characteristicId: charId)
                var config = configs[k] ?? .default
                if let ext = externalAccessEnabled { config.externalAccessEnabled = ext }
                if let webhook = webhookEnabled { config.webhookEnabled = webhook }
                if config == .default {
                    configs.removeValue(forKey: k)
                } else {
                    configs[k] = config
                }
            }
        }
        debouncedSave()
    }

    /// Returns the entire config map in a single actor call for batch lookups.
    func getAllConfigs() -> [String: CharacteristicConfiguration] {
        configs
    }

    func resetAll() {
        configs.removeAll()
        saveNow()
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            let data = try Self.encoder.encode(configs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.config.error("Failed to save device config: \(error)")
        }
    }
}
