import SwiftUI

struct BlockEditorSection: View {
    @Binding var blocks: [BlockDraft]
    let devices: [DeviceModel]
    var allowNesting: Bool = true

    @State private var showingBlockTypePicker = false
    @State private var nestedEditState: NestedEditState?

    struct NestedEditState: Identifiable {
        let id = UUID()
        let parentBlockId: UUID
        let label: String
    }

    var body: some View {
        Section {
            ForEach(Array(blocks.indices), id: \.self) { index in
                BlockEditorRow(
                    block: $blocks[index],
                    devices: devices,
                    allowNesting: allowNesting,
                    onEditNestedBlocks: allowNesting ? { label, _ in
                        nestedEditState = NestedEditState(parentBlockId: blocks[index].id, label: label)
                    } : nil,
                    onDelete: { blocks.remove(at: index) }
                )
            }
            .onDelete { blocks.remove(atOffsets: $0) }
            .onMove { blocks.move(fromOffsets: $0, toOffset: $1) }

            Button {
                showingBlockTypePicker = true
            } label: {
                Label("Add Block", systemImage: "plus.circle")
            }
            .confirmationDialog("Add Block", isPresented: $showingBlockTypePicker) {
                Group {
                    Button("Control Device") { blocks.append(.newControlDevice()) }
                    Button("Webhook") { blocks.append(.newWebhook()) }
                    Button("Log Message") { blocks.append(.newLog()) }
                    Button("Delay") { blocks.append(.newDelay()) }
                    Button("Wait for State") { blocks.append(.newWaitForState()) }
                }
                if allowNesting {
                    Group {
                        Button("If/Else") { blocks.append(.newConditional()) }
                        Button("Repeat") { blocks.append(.newRepeat()) }
                        Button("Repeat While") { blocks.append(.newRepeatWhile()) }
                        Button("Group") { blocks.append(.newGroup()) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } header: {
            HStack {
                Text("Blocks (\(blocks.count))")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        }
        .listRowBackground(Theme.contentBackground)
        .sheet(item: $nestedEditState) { state in
            NestedBlockEditorSheet(
                title: nestedSheetTitle(for: state),
                blocks: nestedBlocksBinding(for: state),
                devices: devices
            )
        }
    }

    private func nestedSheetTitle(for state: NestedEditState) -> String {
        let block = blocks.first(where: { $0.id == state.parentBlockId })
        let blockName = block?.blockType.displayName ?? "Block"
        return "\(blockName) — \(state.label.capitalized) Blocks"
    }

    private func nestedBlocksBinding(for state: NestedEditState) -> Binding<[BlockDraft]> {
        Binding(
            get: {
                guard let block = blocks.first(where: { $0.id == state.parentBlockId }) else { return [] }
                return getNestedBlocks(from: block, label: state.label)
            },
            set: { newBlocks in
                guard let index = blocks.firstIndex(where: { $0.id == state.parentBlockId }) else { return }
                setNestedBlocks(on: &blocks[index], label: state.label, blocks: newBlocks)
            }
        )
    }

    private func getNestedBlocks(from block: BlockDraft, label: String) -> [BlockDraft] {
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

    private func setNestedBlocks(on block: inout BlockDraft, label: String, blocks: [BlockDraft]) {
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
