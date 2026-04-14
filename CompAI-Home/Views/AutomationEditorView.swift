import SwiftUI

struct AutomationEditorView: View {
    enum Mode {
        case create
        case edit(Automation)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
    }

    let mode: Mode
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var automations: [Automation] = []
    var controllerStates: [StateVariable] = []
    let onSave: (AutomationDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AutomationDraft
    @State private var showingDiscardAlert = false
    @State private var showingValidationAlert = false
    @State private var validationErrors: [String] = []
    @State private var showingWarningsAlert = false
    @State private var validationWarnings: [String] = []
    @State private var pendingValidation: AutomationValidation?
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?
    @State private var showContinueOnErrorAlert = false

    /// Nested block sheet state lives here — at a stable level that
    /// does NOT re-render when individual blocks change inside the form.
    @State private var nestedEditState: NestedEditState?

    init(mode: Mode, devices: [DeviceModel], scenes: [SceneModel] = [], automations: [Automation] = [], controllerStates: [StateVariable] = [], onSave: @escaping (AutomationDraft) -> Void) {
        self.mode = mode
        self.devices = devices
        self.scenes = scenes
        self.automations = automations
        self.controllerStates = controllerStates
        self.onSave = onSave
        switch mode {
        case .create:
            _draft = State(initialValue: .empty())
        case let .edit(automation):
            _draft = State(initialValue: AutomationDraft(from: automation, devices: devices))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                TriggerEditorSection(triggers: $draft.triggers, devices: devices, controllerStates: controllerStates, onCopy: showCopyToast)
                ConditionEditorSection(
                    conditionRoot: $draft.conditionRoot,
                    devices: devices,
                    scenes: scenes,
                    continueOnError: draft.continueOnError,
                    allBlocks: draft.allBlockDrafts(),
                    controllerStates: controllerStates
                )
                BlockEditorSection(
                    blocks: $draft.blocks,
                    devices: devices,
                    scenes: scenes,
                    automations: automations,
                    continueOnError: draft.continueOnError,
                    allBlocks: draft.allBlockDrafts(),
                    referencedBlockIds: draft.blockIdsReferencedByConditions(),
                    controllerStates: controllerStates,
                    blockOrdinals: draft.blockOrdinals(),
                    onRequestNestedEdit: { state in
                        nestedEditState = state
                    }
                )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(mode.isCreate ? "New Automation" : "Edit Automation")
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingDiscardAlert = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Discard Changes?", isPresented: $showingDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes will be lost.")
            }
            .alert("Cannot Save", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationErrors.joined(separator: "\n"))
            }
            .alert("Warning", isPresented: $showingWarningsAlert) {
                Button("Save Anyway") { confirmSave() }
                Button("Cancel", role: .cancel) { pendingValidation = nil }
            } message: {
                Text(validationWarnings.joined(separator: "\n"))
            }
            .sheet(item: $nestedEditState) { state in
                NestedBlockEditorSheet(
                    title: BlockEditorSection.nestedSheetTitle(for: state, blocks: draft.blocks),
                    blocks: BlockEditorSection.nestedBlocksBinding(for: state, blocks: $draft.blocks),
                    devices: devices,
                    scenes: scenes,
                    blockOrdinals: draft.blockOrdinals(),
                    controllerStates: controllerStates
                )
            }
            .overlay(alignment: .bottom) {
                if showCopiedToast {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("URL copied to clipboard")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showCopiedToast)
        }
    }

    private func showCopyToast() {
        copiedToastTask?.cancel()
        showCopiedToast = true
        copiedToastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { showCopiedToast = false }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Automation Name", text: $draft.name)
            TextField("Description (optional)", text: $draft.description)
            Toggle("Enabled", isOn: $draft.isEnabled)
                .tint(Theme.Tint.main)
            Toggle("Continue on Error", isOn: Binding(
                get: { draft.continueOnError },
                set: { newValue in
                    if !newValue && draft.hasBlockResultConditions() {
                        showContinueOnErrorAlert = true
                    } else {
                        draft.continueOnError = newValue
                    }
                }
            ))
            .tint(Theme.Tint.main)
        } header: {
            Text("Details")
        }
        .listRowBackground(Theme.contentBackground)
        .alert("Cannot Disable", isPresented: $showContinueOnErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Remove all Block Result conditions from the automation before disabling Continue on Error.")
        }
    }

    private func save() {
        let validation = draft.validate()
        if !validation.isValid {
            validationErrors = validation.errors
            showingValidationAlert = true
            return
        }
        if !validation.warnings.isEmpty {
            validationWarnings = validation.warnings
            pendingValidation = validation
            showingWarningsAlert = true
            return
        }
        onSave(draft)
        dismiss()
    }

    private func confirmSave() {
        onSave(draft)
        dismiss()
    }
}

#Preview("Create") {
    AutomationEditorView(
        mode: .create,
        devices: PreviewData.sampleDevices,
        scenes: PreviewData.sampleScenes,
        onSave: { _ in }
    )
}

#Preview("Edit") {
    AutomationEditorView(
        mode: .edit(PreviewData.sampleAutomations[0]),
        devices: PreviewData.sampleDevices,
        scenes: PreviewData.sampleScenes,
        onSave: { _ in }
    )
}
