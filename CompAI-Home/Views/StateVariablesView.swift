import SwiftUI
import Combine

struct StateVariablesView: View {
    let storageService: StateVariableStorageService
    var automations: [Automation] = []
    @Environment(\.dismiss) private var dismiss

    @State private var variables: [StateVariable] = []
    @State private var showAddSheet = false
    @State private var editingVariable: StateVariable?
    @State private var deleteTarget: StateVariable?
    @State private var cancellable: AnyCancellable?

    var body: some View {
        List {
            if variables.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 40))
                            .foregroundStyle(.teal)
                        Text("No Controller States")
                            .font(.headline)
                        Text("Controller states store persistent data that automations can read and modify across executions.")
                            .font(.subheadline)
                            .foregroundColor(Theme.Text.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(variables) { variable in
                        Button {
                            editingVariable = variable
                        } label: {
                            stateRow(variable)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        guard let idx = offsets.first else { return }
                        deleteTarget = variables[idx]
                    }
                } header: {
                    Text("\(variables.count) state\(variables.count == 1 ? "" : "s")")
                }
            }
        }
        .navigationTitle("Controller States")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Delete Controller State?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                guard let target = deleteTarget else { return }
                Task { await storageService.delete(id: target.id) }
                deleteTarget = nil
            }
        } message: {
            if let target = deleteTarget {
                let refs = StateVariableReferenceScanner.automationsReferencing(stateName: target.name, in: automations)
                if refs.isEmpty {
                    Text("This will permanently remove \"\(target.label)\".")
                } else {
                    Text("Warning: \"\(target.label)\" is used in \(refs.count) automation\(refs.count == 1 ? "" : "s"):\n\(refs.map(\.name).joined(separator: ", "))\n\nThose automations may fail after deletion.")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddControllerStateSheet(storageService: storageService)
        }
        .sheet(item: $editingVariable) { variable in
            EditControllerStateSheet(
                storageService: storageService,
                variable: variable,
                referencingAutomations: StateVariableReferenceScanner.automationsReferencing(stateName: variable.name, in: automations)
            )
        }
        .task {
            variables = await storageService.getAll()
            cancellable = storageService.variablesSubject.receive(on: DispatchQueue.main).sink { newVars in
                variables = newVars
            }
        }
    }

    @ViewBuilder
    private func stateRow(_ variable: StateVariable) -> some View {
        HStack(spacing: 12) {
            Image(systemName: variable.type.icon)
                .font(.title3)
                .foregroundStyle(.teal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(variable.label)
                    .font(.body)
                    .fontWeight(.medium)
                Text(variable.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.Text.tertiary)
            }

            Spacer()

            Text(variable.displayValue)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(Theme.Text.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.Text.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Name Validation

private func isValidStateName(_ name: String) -> Bool {
    guard !name.isEmpty else { return false }
    let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
    return name.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func nameValidationError(_ name: String) -> String? {
    if name.isEmpty { return nil }
    if name.contains(" ") { return "Name cannot contain spaces" }
    if name != name.lowercased() { return "Name must be lowercase" }
    if !isValidStateName(name) { return "Only letters, numbers, and underscores allowed" }
    return nil
}

// MARK: - Add Controller State Sheet

private struct AddControllerStateSheet: View {
    let storageService: StateVariableStorageService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var displayName = ""
    @State private var variableType: StateVariableType = .number
    @State private var numberValue: Double = 0
    @State private var numberText: String = "0"
    @State private var stringValue: String = ""
    @State private var boolValue: Bool = false
    @State private var numberError: String?

    private var nameError: String? { nameValidationError(name) }
    private var canCreate: Bool { !name.isEmpty && nameError == nil && numberError == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identifier") {
                    TextField("my_counter", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if !name.isEmpty {
                        Text("Only lowercase letters, numbers, and underscores")
                            .font(.caption)
                            .foregroundColor(Theme.Text.tertiary)
                    }
                }

                Section("Display Name") {
                    TextField("e.g. Living Room Counter", text: $displayName)
                }

                Section("Type") {
                    Picker("Type", selection: $variableType) {
                        ForEach(StateVariableType.allCases) { t in
                            Label(t.displayName, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Initial Value") {
                    switch variableType {
                    case .number:
                        TextField("0", text: $numberText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: numberText) { newVal in
                                if newVal.isEmpty {
                                    numberError = nil
                                    numberValue = 0
                                } else if let parsed = Double(newVal) {
                                    numberError = nil
                                    numberValue = parsed
                                } else {
                                    numberError = "Must be a valid number"
                                }
                            }
                        if let error = numberError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    case .string:
                        TextField("Enter text...", text: $stringValue)
                    case .boolean:
                        Toggle("Value", isOn: $boolValue)
                    }
                }
            }
            .navigationTitle("New Controller State")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            let value: Any = {
                                switch variableType {
                                case .number: return numberValue
                                case .string: return stringValue
                                case .boolean: return boolValue
                                }
                            }()
                            let variable = StateVariable(name: name, displayName: displayName.isEmpty ? nil : displayName, type: variableType, value: AnyCodable(value))
                            await storageService.create(variable)
                            dismiss()
                        }
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }
}

// MARK: - Edit Controller State Sheet

private struct EditControllerStateSheet: View {
    let storageService: StateVariableStorageService
    let variable: StateVariable
    var referencingAutomations: [Automation] = []
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var displayName: String
    @State private var numberValue: Double
    @State private var numberText: String
    @State private var stringValue: String
    @State private var boolValue: Bool
    @State private var numberError: String?

    private var nameError: String? { nameValidationError(name) }
    private var canSave: Bool { !name.isEmpty && nameError == nil && numberError == nil }

    init(storageService: StateVariableStorageService, variable: StateVariable, referencingAutomations: [Automation] = []) {
        self.storageService = storageService
        self.variable = variable
        self.referencingAutomations = referencingAutomations
        _name = State(initialValue: variable.name)
        _displayName = State(initialValue: variable.displayName ?? "")
        let numVal = variable.numberValue ?? 0
        _numberValue = State(initialValue: numVal)
        _numberText = State(initialValue: variable.type == .number ? variable.displayValue : "0")
        _stringValue = State(initialValue: variable.stringValue ?? "")
        _boolValue = State(initialValue: variable.boolValue ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identifier") {
                    TextField("my_counter", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))

                    if let error = nameError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Display Name") {
                    TextField("e.g. Living Room Counter", text: $displayName)
                }

                Section {
                    HStack {
                        Text("Type")
                        Spacer()
                        Label(variable.type.displayName, systemImage: variable.type.icon)
                            .foregroundColor(Theme.Text.secondary)
                    }
                }

                Section("Value") {
                    switch variable.type {
                    case .number:
                        TextField("0", text: $numberText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: numberText) { newVal in
                                if newVal.isEmpty {
                                    numberError = nil
                                    numberValue = 0
                                } else if let parsed = Double(newVal) {
                                    numberError = nil
                                    numberValue = parsed
                                } else {
                                    numberError = "Must be a valid number"
                                }
                            }
                        if let error = numberError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    case .string:
                        TextField("Enter text...", text: $stringValue)
                    case .boolean:
                        Toggle("Value", isOn: $boolValue)
                    }
                }

                Section {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(variable.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(Theme.Text.secondary)
                    }
                    HStack {
                        Text("Updated")
                        Spacer()
                        Text(variable.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(Theme.Text.secondary)
                    }
                }

                if !referencingAutomations.isEmpty {
                    Section {
                        ForEach(referencingAutomations) { automation in
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text(automation.name)
                                    .font(.subheadline)
                            }
                        }
                    } header: {
                        Text("Used in \(referencingAutomations.count) automation\(referencingAutomations.count == 1 ? "" : "s")")
                    } footer: {
                        Text("Renaming or deleting this state may affect these automations.")
                    }
                }
            }
            .navigationTitle("Edit Controller State")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let value: Any = {
                                switch variable.type {
                                case .number: return numberValue
                                case .string: return stringValue
                                case .boolean: return boolValue
                                }
                            }()
                            await storageService.updateVariable(id: variable.id) { v in
                                v.name = name
                                v.displayName = displayName.isEmpty ? nil : displayName
                                v.value = AnyCodable(value)
                            }
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
