import Foundation
import Combine

actor StateVariableStorageService {
    private var variables: [UUID: StateVariable] = [:]
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    nonisolated let variablesSubject = PassthroughSubject<[StateVariable], Never>()

    init() {
        let appDir = FileManager.appSupportDirectory
        self.fileURL = appDir.appendingPathComponent("state_variables.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.iso8601.decode([StateVariable].self, from: data) {
            for variable in saved {
                self.variables[variable.id] = variable
            }
        }
    }

    // MARK: - Read

    func getAll() -> [StateVariable] {
        Array(variables.values).sorted { $0.name < $1.name }
    }

    func get(id: UUID) -> StateVariable? {
        variables[id]
    }

    func getByName(_ name: String) -> StateVariable? {
        variables.values.first(where: { $0.name == name })
    }

    /// Resolve a `StateVariableRef` to the actual variable.
    func resolve(_ ref: StateVariableRef) -> StateVariable? {
        switch ref {
        case let .byName(name): return getByName(name)
        case let .byId(id): return get(id: id)
        }
    }

    // MARK: - Create

    @discardableResult
    func create(_ variable: StateVariable) -> StateVariable {
        variables[variable.id] = variable
        publishAndSave()
        return variable
    }

    // MARK: - Update

    @discardableResult
    func update(id: UUID, value: AnyCodable) -> StateVariable? {
        guard var variable = variables[id] else { return nil }
        variable.value = value
        variable.updatedAt = Date()
        variables[id] = variable
        publishAndSave()
        return variable
    }

    @discardableResult
    func update(id: UUID, name: String) -> StateVariable? {
        guard var variable = variables[id] else { return nil }
        variable.name = name
        variable.updatedAt = Date()
        variables[id] = variable
        publishAndSave()
        return variable
    }

    @discardableResult
    func updateVariable(id: UUID, mutate: (inout StateVariable) -> Void) -> StateVariable? {
        guard var variable = variables[id] else { return nil }
        mutate(&variable)
        variable.updatedAt = Date()
        variables[id] = variable
        publishAndSave()
        return variable
    }

    // MARK: - Delete

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard variables.removeValue(forKey: id) != nil else { return false }
        publishAndSave()
        return true
    }

    @discardableResult
    func deleteByName(_ name: String) -> Bool {
        guard let variable = getByName(name) else { return false }
        return delete(id: variable.id)
    }

    func deleteAll() {
        variables.removeAll()
        publishAndSave()
    }

    // MARK: - Persistence

    private func publishAndSave() {
        variablesSubject.send(getAll())
        debouncedSave()
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
            let allVariables = getAll()
            let data = try JSONEncoder.iso8601Pretty.encode(allVariables)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            AppLogger.general.error("Failed to save state variables: \(error)")
        }
    }
}
