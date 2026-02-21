import SwiftUI

/// Identifiable state for presenting the nested block editor sheet.
/// Uses a deterministic `id` (parentBlockId + label) so SwiftUI treats
/// re-creations with the same values as the *same* item — preventing
/// unwanted sheet dismissals when the parent's block array changes.
struct NestedEditState: Identifiable {
    var id: String { "\(parentBlockId.uuidString)-\(label)" }
    let parentBlockId: UUID
    let label: String
}

struct BlockEditorSection: View {
    @Binding var blocks: [BlockDraft]
    let devices: [DeviceModel]
    var allowNesting: Bool = true
    var workflows: [Workflow] = []

    /// When non-nil the parent (WorkflowEditorView) uses this to open the nested-block sheet.
    var onRequestNestedEdit: ((NestedEditState) -> Void)?

    /// When true, all blocks collapse and `.onMove` is active so the user
    /// can drag rows to reorder. No interactive controls are visible in
    /// this mode, avoiding gesture conflicts with sliders/pickers.
    @State private var isReorderMode = false

    var body: some View {
        Section {
            ForEach($blocks) { $block in
                blockEditorRow(for: $block)
            }
            .onMove { from, to in
                blocks.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { blocks.remove(atOffsets: $0) }
            .moveDisabled(!isReorderMode)

            // Use a Menu instead of confirmationDialog — works correctly both in
            // top-level forms and nested sheets on Mac Catalyst.
            if !isReorderMode {
                Menu {
                    Button("Control Device", systemImage: "house.fill") {
                        blocks.append(.newControlDevice())
                    }
                    Button("Webhook", systemImage: "globe") {
                        blocks.append(.newWebhook())
                    }
                    Button("Log Message", systemImage: "text.bubble") {
                        blocks.append(.newLog())
                    }
                    Button("Delay", systemImage: "clock") {
                        blocks.append(.newDelay())
                    }
                    Button("Wait for State", systemImage: "hourglass") {
                        blocks.append(.newWaitForState())
                    }
                    if allowNesting {
                        Divider()
                        Button("If/Else", systemImage: "arrow.triangle.branch") {
                            blocks.append(.newConditional())
                        }
                        Button("Repeat", systemImage: "repeat") {
                            blocks.append(.newRepeat())
                        }
                        Button("Repeat While", systemImage: "repeat.circle") {
                            blocks.append(.newRepeatWhile())
                        }
                        Button("Group", systemImage: "folder") {
                            blocks.append(.newGroup())
                        }
                        Button("Stop", systemImage: "stop.circle.fill") {
                            blocks.append(.newStop())
                        }
                        Button("Execute Workflow", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                            blocks.append(.newExecuteWorkflow())
                        }
                    }
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                        .foregroundColor(Theme.Tint.main)
                }
            }
        } header: {
            HStack {
                Text("Blocks (\(blocks.count))")
                Spacer()
                if isReorderMode {
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isReorderMode = false
                        }
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Tint.main)
                } else if blocks.count > 1 {
                    Button("Reorder") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isReorderMode = true
                        }
                    }
                    .font(.caption)
                    .foregroundColor(Theme.Tint.main)
                }
            }
        }
        .listRowBackground(Theme.contentBackground)
    }

    // MARK: - Row Factory

    private func blockEditorRow(for block: Binding<BlockDraft>) -> BlockEditorRow {
        let blockId = block.wrappedValue.id
        return BlockEditorRow(
            block: block,
            devices: devices,
            allowNesting: allowNesting,
            onEditNestedBlocks: allowNesting ? { label, _ in
                onRequestNestedEdit?(NestedEditState(parentBlockId: blockId, label: label))
            } : nil,
            onDelete: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    blocks.removeAll(where: { $0.id == blockId })
                }
            },
            onDuplicate: {
                guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
                let copy = blocks[idx].deepCopy()
                withAnimation(.easeInOut(duration: 0.25)) {
                    blocks.insert(copy, at: idx + 1)
                }
            },
            isReorderMode: isReorderMode,
            workflows: workflows
        )
    }
}

// MARK: - Nested Block Helpers

extension BlockEditorSection {
    static func nestedSheetTitle(for state: NestedEditState, blocks: [BlockDraft]) -> String {
        let block = blocks.first(where: { $0.id == state.parentBlockId })
        let blockName = block?.blockType.displayName ?? "Block"
        return "\(blockName) — \(state.label.capitalized) Blocks"
    }

    static func nestedBlocksBinding(for state: NestedEditState, blocks: Binding<[BlockDraft]>) -> Binding<[BlockDraft]> {
        Binding(
            get: {
                guard let block = blocks.wrappedValue.first(where: { $0.id == state.parentBlockId }) else { return [] }
                return getNestedBlocks(from: block, label: state.label)
            },
            set: { newBlocks in
                guard let index = blocks.wrappedValue.firstIndex(where: { $0.id == state.parentBlockId }) else { return }
                setNestedBlocks(on: &blocks.wrappedValue[index], label: state.label, blocks: newBlocks)
            }
        )
    }

    static func getNestedBlocks(from block: BlockDraft, label: String) -> [BlockDraft] {
        switch block.blockType {
        case .conditional(let d):
            return label == "then" ? d.thenBlocks : d.elseBlocks
        case .repeatBlock(let d):
            return d.blocks
        case .repeatWhile(let d):
            return d.blocks
        case .group(let d):
            return d.blocks
        default:
            return []
        }
    }

    static func setNestedBlocks(on block: inout BlockDraft, label: String, blocks: [BlockDraft]) {
        switch block.blockType {
        case .conditional(var d):
            if label == "then" { d.thenBlocks = blocks } else { d.elseBlocks = blocks }
            block.blockType = .conditional(d)
        case .repeatBlock(var d):
            d.blocks = blocks
            block.blockType = .repeatBlock(d)
        case .repeatWhile(var d):
            d.blocks = blocks
            block.blockType = .repeatWhile(d)
        case .group(var d):
            d.blocks = blocks
            block.blockType = .group(d)
        default:
            break
        }
    }
}

// MARK: - Nested Block Editor Sheet

struct NestedBlockEditorSheet: View {
    let title: String
    @Binding var blocks: [BlockDraft]
    let devices: [DeviceModel]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                BlockEditorSection(blocks: $blocks, devices: devices, allowNesting: false)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.mainBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
