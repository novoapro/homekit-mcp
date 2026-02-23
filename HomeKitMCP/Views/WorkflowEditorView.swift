import SwiftUI

struct WorkflowEditorView: View {
    enum Mode {
        case create
        case edit(Workflow)

        var isCreate: Bool {
            if case .create = self { return true }
            return false
        }
    }

    let mode: Mode
    let devices: [DeviceModel]
    var scenes: [SceneModel] = []
    var workflows: [Workflow] = []
    let onSave: (WorkflowDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkflowDraft
    @State private var showingDiscardAlert = false
    @State private var showingValidationAlert = false
    @State private var validationErrors: [String] = []
    @State private var showCopiedToast = false
    @State private var copiedToastTask: Task<Void, Never>?

    /// Nested block sheet state lives here — at a stable level that
    /// does NOT re-render when individual blocks change inside the form.
    @State private var nestedEditState: NestedEditState?

    init(mode: Mode, devices: [DeviceModel], scenes: [SceneModel] = [], workflows: [Workflow] = [], onSave: @escaping (WorkflowDraft) -> Void) {
        self.mode = mode
        self.devices = devices
        self.scenes = scenes
        self.workflows = workflows
        self.onSave = onSave
        switch mode {
        case .create:
            _draft = State(initialValue: .empty())
        case let .edit(workflow):
            // Migrate orphaned device/service UUIDs (e.g., after iCloud backup restore to a different machine)
            let migrated = WorkflowMigrationService.migrate(workflow, using: devices)
            _draft = State(initialValue: WorkflowDraft(from: migrated.workflow, devices: devices))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                TriggerEditorSection(triggers: $draft.triggers, devices: devices, onCopy: showCopyToast)
                ConditionEditorSection(conditionRoot: $draft.conditionRoot, devices: devices, scenes: scenes)
                BlockEditorSection(
                    blocks: $draft.blocks,
                    devices: devices,
                    scenes: scenes,
                    workflows: workflows,
                    onRequestNestedEdit: { state in
                        nestedEditState = state
                    }
                )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .navigationTitle(mode.isCreate ? "New Workflow" : "Edit Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            .sheet(item: $nestedEditState) { state in
                NestedBlockEditorSheet(
                    title: BlockEditorSection.nestedSheetTitle(for: state, blocks: draft.blocks),
                    blocks: BlockEditorSection.nestedBlocksBinding(for: state, blocks: $draft.blocks),
                    devices: devices,
                    scenes: scenes
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
            TextField("Workflow Name", text: $draft.name)
            TextField("Description (optional)", text: $draft.description)
            Toggle("Enabled", isOn: $draft.isEnabled)
                .tint(Theme.Tint.main)
            Toggle("Continue on Error", isOn: $draft.continueOnError)
                .tint(Theme.Tint.main)
        } header: {
            Text("Details")
        }
        .listRowBackground(Theme.contentBackground)
    }

    private func save() {
        let validation = draft.validate()
        if validation.isValid {
            onSave(draft)
            dismiss()
        } else {
            validationErrors = validation.errors
            showingValidationAlert = true
        }
    }
}
