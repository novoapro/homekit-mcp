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
    var scenes: [SceneModel] = []
    var allowNesting: Bool = true
    var automations: [Automation] = []
    var continueOnError: Bool = false
    var allBlocks: [BlockDraft] = []
    var referencedBlockIds: Set<UUID> = []
    var controllerStates: [StateVariable] = []
    /// 1-based execution order index for each block (keyed by block ID).
    var blockOrdinals: [UUID: Int] = [:]

    /// When non-nil the parent (AutomationEditorView) uses this to open the nested-block sheet.
    var onRequestNestedEdit: ((NestedEditState) -> Void)?

    /// When true, all blocks collapse and `.onMove` is active so the user
    /// can drag rows to reorder. No interactive controls are visible in
    /// this mode, avoiding gesture conflicts with sliders/pickers.
    @State private var isReorderMode = false
    @State private var showReferencedBlockAlert = false

    var body: some View {
        Section {
            ForEach($blocks) { $block in
                blockEditorRow(for: $block, isFirst: blocks.first?.id == block.id)
            }
            .onMove { from, to in
                blocks.move(fromOffsets: from, toOffset: to)
            }
            .onDelete { offsets in
                let idsToRemove = offsets.map { blocks[$0].id }
                if idsToRemove.contains(where: { referencedBlockIds.contains($0) }) {
                    showReferencedBlockAlert = true
                    return
                }
                blocks.removeAll { idsToRemove.contains($0.id) }
            }
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
                    Button("Run Scene", systemImage: "play.rectangle.fill") {
                        blocks.append(.newRunScene())
                    }
                    Button("Global Value", systemImage: "cylinder.split.1x2") {
                        blocks.append(.newStateVariable())
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
                        Button("Execute Automation", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                            blocks.append(.newExecuteAutomation())
                        }
                    }
                    Divider()
                    Button("Return", systemImage: "arrow.uturn.backward.circle.fill") {
                        blocks.append(.newStop())
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Add Block")
                    }
                    .foregroundColor(Theme.Tint.main)
                }
                .listRowBackground(Theme.contentBackground)
                .listRowSeparator(.hidden)
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
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Tint.main)
                } else if blocks.count > 1 {
                    Button("Reorder") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isReorderMode = true
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(Theme.Tint.main)
                }
            }
        }
        .alert("Cannot Delete Block", isPresented: $showReferencedBlockAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This block is referenced by a Block Result condition. Remove the condition first before deleting this block.")
        }
    }

    // MARK: - Row Factory

    private func blockEditorRow(for block: Binding<BlockDraft>, isFirst: Bool) -> some View {
        let blockId = block.wrappedValue.id
        let isFlowControl = block.wrappedValue.blockType.isFlowControl
        let accentColor = isFlowControl ? Theme.Tint.secondary : Theme.Tint.main
        let isReferenced = referencedBlockIds.contains(blockId)
        let targets = Self.containerTargets(excluding: blockId, in: blocks)
        return BlockEditorRow(
            block: block,
            devices: devices,
            scenes: scenes,
            allowNesting: allowNesting,
            continueOnError: continueOnError,
            allBlocks: allBlocks,
            isReferencedByCondition: isReferenced,
            onEditNestedBlocks: allowNesting ? { label, _ in
                onRequestNestedEdit?(NestedEditState(parentBlockId: blockId, label: label))
            } : nil,
            onDelete: {
                if isReferenced {
                    showReferencedBlockAlert = true
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        blocks.removeAll(where: { $0.id == blockId })
                    }
                }
            },
            onDuplicate: {
                guard let idx = blocks.firstIndex(where: { $0.id == blockId }) else { return }
                let copy = blocks[idx].deepCopy()
                withAnimation(.easeInOut(duration: 0.25)) {
                    blocks.insert(copy, at: idx + 1)
                }
            },
            moveTargets: targets,
            onMoveToContainer: targets.isEmpty ? nil : { targetId, targetLabel in
                withAnimation(.easeInOut(duration: 0.25)) {
                    Self.moveBlockToContainer(
                        blockId: blockId,
                        targetContainerId: targetId,
                        targetLabel: targetLabel,
                        blocks: &blocks
                    )
                }
            },
            isReorderMode: isReorderMode,
            automations: automations,
            ordinal: blockOrdinals[blockId],
            blockOrdinals: blockOrdinals,
            controllerStates: controllerStates
        )
        .listRowBackground(
            VStack(spacing: 0) {
                if !isFirst && !isReorderMode {
                    Rectangle()
                        .fill(Color(UIColor.separator))
                        .frame(height: 3)
                }
                HStack(spacing: 0) {
                    accentColor.frame(width: Theme.Block.accentBarWidth)
                    Theme.contentBackground
                }
            }
        )
    }
}

// MARK: - Move-to-Container Helpers

struct MoveTarget: Identifiable {
    var id: String { "\(containerBlockId.uuidString)-\(label)" }
    let containerBlockId: UUID
    let label: String
    let description: String
    let icon: String
}

extension BlockEditorSection {
    /// Returns available container targets at the same level for a given block.
    static func containerTargets(excluding blockId: UUID, in blocks: [BlockDraft]) -> [MoveTarget] {
        var targets: [MoveTarget] = []
        for block in blocks where block.id != blockId {
            switch block.blockType {
            case .conditional(let d):
                let name = d.name.isEmpty ? "If/Else" : d.name
                targets.append(MoveTarget(containerBlockId: block.id, label: "then", description: "\(name) → Then", icon: block.blockType.icon))
                targets.append(MoveTarget(containerBlockId: block.id, label: "else", description: "\(name) → Else", icon: block.blockType.icon))
            case .repeatBlock(let d):
                let name = d.name.isEmpty ? "Repeat" : d.name
                targets.append(MoveTarget(containerBlockId: block.id, label: "blocks", description: "\(name) → Blocks", icon: block.blockType.icon))
            case .repeatWhile(let d):
                let name = d.name.isEmpty ? "Repeat While" : d.name
                targets.append(MoveTarget(containerBlockId: block.id, label: "blocks", description: "\(name) → Blocks", icon: block.blockType.icon))
            case .group(let d):
                let name = d.name.isEmpty ? (d.label.isEmpty ? "Group" : d.label) : d.name
                targets.append(MoveTarget(containerBlockId: block.id, label: "blocks", description: "\(name) → Blocks", icon: block.blockType.icon))
            default:
                break
            }
        }
        return targets
    }

    /// Moves a block from its current position into a target container's nested blocks.
    static func moveBlockToContainer(
        blockId: UUID,
        targetContainerId: UUID,
        targetLabel: String,
        blocks: inout [BlockDraft]
    ) {
        guard let sourceIndex = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let block = blocks.remove(at: sourceIndex)

        // Re-find target index after removal (it may have shifted)
        guard let targetIndex = blocks.firstIndex(where: { $0.id == targetContainerId }) else {
            // Safety: put block back if target disappeared
            blocks.insert(block, at: min(sourceIndex, blocks.count))
            return
        }

        var nested = getNestedBlocks(from: blocks[targetIndex], label: targetLabel)
        nested.append(block)
        setNestedBlocks(on: &blocks[targetIndex], label: targetLabel, blocks: nested)
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
    var scenes: [SceneModel] = []
    var blockOrdinals: [UUID: Int] = [:]
    var controllerStates: [StateVariable] = []
    @Environment(\.dismiss) private var dismiss
    @State private var nestedEditState: NestedEditState?

    var body: some View {
        NavigationStack {
            Form {
                BlockEditorSection(
                    blocks: $blocks,
                    devices: devices,
                    scenes: scenes,
                    allowNesting: true,
                    controllerStates: controllerStates,
                    blockOrdinals: blockOrdinals,
                    onRequestNestedEdit: { state in
                        nestedEditState = state
                    }
                )
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
            .sheet(item: $nestedEditState) { state in
                NestedBlockEditorSheet(
                    title: BlockEditorSection.nestedSheetTitle(for: state, blocks: blocks),
                    blocks: BlockEditorSection.nestedBlocksBinding(for: state, blocks: $blocks),
                    devices: devices,
                    scenes: scenes,
                    blockOrdinals: blockOrdinals,
                    controllerStates: controllerStates
                )
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var blocks = PreviewData.sampleBlockDrafts

        var body: some View {
            NavigationStack {
                Form {
                    BlockEditorSection(
                        blocks: $blocks,
                        devices: PreviewData.sampleDevices,
                        scenes: PreviewData.sampleScenes
                    )
                }
                .navigationTitle("Blocks")
            }
        }
    }
    return PreviewWrapper()
}
