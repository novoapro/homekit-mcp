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

    /// When non-nil the parent (WorkflowEditorView) uses this to open the nested-block sheet.
    var onRequestNestedEdit: ((NestedEditState) -> Void)?

    var body: some View {
        Section {
            ForEach($blocks) { $block in
                BlockEditorRow(
                    block: $block,
                    devices: devices,
                    allowNesting: allowNesting,
                    onEditNestedBlocks: allowNesting ? { label, _ in
                        onRequestNestedEdit?(NestedEditState(parentBlockId: block.id, label: label))
                    } : nil,
                    onDelete: { blocks.removeAll(where: { $0.id == block.id }) }
                )
            }
            .onDelete { blocks.remove(atOffsets: $0) }

            // Use a Menu instead of confirmationDialog — works correctly both in
            // top-level forms and nested sheets on Mac Catalyst.
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
                }
            } label: {
                Label("Add Block", systemImage: "plus.circle")
                    .foregroundColor(Theme.Tint.main)
            }
        } header: {
            Text("Blocks (\(blocks.count))")
        }
        .listRowBackground(Theme.contentBackground)
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
