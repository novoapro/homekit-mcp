import { Component, inject, signal, OnInit, computed } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';
import { Location } from '@angular/common';
import { ApiService } from '../../core/services/api.service';
import { IconComponent } from '../../shared/components/icon.component';
import { TriggerEditorComponent } from './components/trigger-editor.component';
import { ConditionEditorComponent } from './components/condition-editor.component';
import { ConditionGroupEditorComponent } from './components/condition-group-editor.component';
import { ExpandableBlockCardComponent } from './components/expandable-block-card.component';
import { AddBlockSheetComponent } from './components/add-block-sheet.component';
import { newBlockDraft } from './components/block-editor.component';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';
import { MatChipsModule } from '@angular/material/chips';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatExpansionModule } from '@angular/material/expansion';
import { COMMA, ENTER } from '@angular/cdk/keycodes';
import { MatChipInputEvent } from '@angular/material/chips';
import { TextFieldModule } from '@angular/cdk/text-field';
import { CdkDragDrop, CdkDrag, CdkDropList, moveItemInArray } from '@angular/cdk/drag-drop';
import { DeviceRegistryService } from '../../core/services/device-registry.service';
import { WorkflowDraft, WorkflowTriggerDraft, WorkflowConditionDraft, WorkflowBlockDraft, emptyDraft, newUUID } from './workflow-editor.types';
import { validateDraft } from './workflow-editor-validation';
import { draftToPayload, definitionToDraft, triggerAutoName, conditionAutoName, blockAutoName } from './workflow-editor-utils';

// --- Panel types (triggers & conditions only) ---

type PanelItemKind = 'trigger' | 'condition' | 'conditionGroup';

interface NestedPath {
  field: 'thenBlocks' | 'elseBlocks' | 'blocks' | 'conditions' | 'condition';
  index: number;
  nested?: NestedPath;
}

interface ItemPath {
  section: 'triggers' | 'conditions' | 'blocks';
  index: number;
  nested?: NestedPath;
}

interface PanelFrame {
  kind: PanelItemKind;
  path: ItemPath;
  label: string;
}

// --- Nesting stack for blocks ---

interface NestingFrame {
  parentBlockId: string;  // _draftId of parent block
  field: 'thenBlocks' | 'elseBlocks' | 'blocks';
  label: string;
}

// --- Constants ---

const TRIGGER_ICONS: Record<string, string> = {
  deviceStateChange: 'house', schedule: 'clock', sunEvent: 'sun-max-fill',
  webhook: 'link', workflow: 'arrow-triangle-branch', compound: 'arrow-triangle-branch',
};

const TRIGGER_BADGES: Record<string, string> = {
  deviceStateChange: 'Device', schedule: 'Schedule', sunEvent: 'Sun',
  webhook: 'Webhook', workflow: 'Callable', compound: 'Compound',
};

function newTriggerDraft(): WorkflowTriggerDraft {
  return { _draftId: newUUID(), type: 'deviceStateChange', condition: { type: 'changed' } };
}

function newRootConditionGroup(): WorkflowConditionDraft {
  return { _draftId: newUUID(), type: 'and', conditions: [] };
}

@Component({
  selector: 'app-workflow-editor',
  standalone: true,
  imports: [
    IconComponent, TriggerEditorComponent, ConditionEditorComponent, ConditionGroupEditorComponent,
    ExpandableBlockCardComponent, AddBlockSheetComponent,
    MatFormFieldModule, MatInputModule, MatSlideToggleModule, MatChipsModule,
    MatButtonModule, MatIconModule, MatExpansionModule, TextFieldModule,
    CdkDrag, CdkDropList,
  ],
  templateUrl: './workflow-editor.component.html',
  styleUrl: './workflow-editor.component.css',
})
export class WorkflowEditorComponent implements OnInit {
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);
  private api = inject(ApiService);
  registry = inject(DeviceRegistryService);

  isEditMode = signal(false);
  workflowId = signal<string | null>(null);
  isLoading = signal(false);
  isSaving = signal(false);
  loadError = signal<string | null>(null);
  saveError = signal<string | null>(null);

  draft = signal<WorkflowDraft>(emptyDraft());
  tagInput = signal('');
  showSettings = signal(false);

  readonly validationErrors = computed(() => validateDraft(this.draft()));
  readonly isValid = computed(() => this.validationErrors().length === 0);

  readonly separatorKeyCodes = [ENTER, COMMA] as const;

  // =============================================
  // Panel state (triggers & conditions ONLY)
  // =============================================
  panelStack = signal<PanelFrame[]>([]);
  readonly isPanelOpen = computed(() => this.panelStack().length > 0);
  readonly currentFrame = computed(() => {
    const stack = this.panelStack();
    return stack.length > 0 ? stack[stack.length - 1] : null;
  });
  readonly breadcrumbs = computed(() => this.panelStack().map(f => f.label));

  readonly currentEditItem = computed(() => {
    const frame = this.currentFrame();
    if (!frame) return null;
    return this.resolveItemAtPath(frame.path);
  });

  readonly isGuardConditionContext = computed(() => {
    const stack = this.panelStack();
    return stack.length > 0 && stack[0].path.section === 'conditions';
  });

  // =============================================
  // Block nesting stack (replaces panel for blocks)
  // =============================================
  nestingStack = signal<NestingFrame[]>([]);
  expandedBlockIds = signal<Set<string>>(new Set());
  addBlockSheetOpen = signal(false);
  reorderMode = signal(false);
  nestingTransition = signal<'none' | 'push' | 'pop'>('none');

  /** Resolve the current block list based on nesting depth */
  readonly currentBlocks = computed((): WorkflowBlockDraft[] => {
    const stack = this.nestingStack();
    if (stack.length === 0) return this.draft().blocks;

    let blocks: WorkflowBlockDraft[] = this.draft().blocks;
    for (const frame of stack) {
      const parent = blocks.find(b => b._draftId === frame.parentBlockId);
      if (!parent) return [];
      blocks = (parent as any)[frame.field] || [];
    }
    return blocks;
  });

  /** Breadcrumb trail for block nesting */
  readonly nestingBreadcrumbs = computed(() => {
    const crumbs: { label: string; level: number }[] = [
      { label: 'Blocks', level: -1 }
    ];
    this.nestingStack().forEach((f, i) => crumbs.push({ label: f.label, level: i }));
    return crumbs;
  });

  /** Depth-first ordinal map across ALL blocks */
  readonly blockOrdinals = computed(() => {
    const ordinals = new Map<string, number>();
    let counter = 1;
    function walk(blocks: WorkflowBlockDraft[]) {
      for (const b of blocks) {
        ordinals.set(b._draftId, counter++);
        if (b.thenBlocks) walk(b.thenBlocks);
        if (b.elseBlocks) walk(b.elseBlocks);
        if (b.blocks) walk(b.blocks);
      }
    }
    walk(this.draft().blocks);
    return ordinals;
  });

  // =============================================
  // Icon/badge lookups
  // =============================================
  triggerIcon(t: WorkflowTriggerDraft): string { return TRIGGER_ICONS[t.type] || 'bolt'; }
  triggerBadge(t: WorkflowTriggerDraft): string { return TRIGGER_BADGES[t.type] || t.type; }
  triggerName(t: WorkflowTriggerDraft): string { return t.name || triggerAutoName(t, this.registry); }

  // =============================================
  // Panel navigation (triggers & conditions)
  // =============================================
  openPanel(kind: PanelItemKind, section: 'triggers' | 'conditions', index: number, label: string): void {
    this.panelStack.set([{ kind, path: { section, index }, label }]);
  }

  pushPanel(kind: PanelItemKind, path: ItemPath, label: string): void {
    this.panelStack.update(stack => [...stack, { kind, path, label }]);
  }

  popPanel(): void {
    this.panelStack.update(stack => stack.length > 1 ? stack.slice(0, -1) : []);
  }

  popToLevel(level: number): void {
    this.panelStack.update(stack => stack.slice(0, level + 1));
  }

  closePanel(): void {
    this.panelStack.set([]);
  }

  // --- Path resolution (still used for triggers/conditions panel) ---
  private resolveItemAtPath(path: ItemPath): any {
    const d = this.draft();
    let list: any[];
    switch (path.section) {
      case 'triggers': list = d.triggers; break;
      case 'conditions': list = d.conditions; break;
      case 'blocks': list = d.blocks; break;
    }
    let item = list[path.index];
    let nested = path.nested;
    while (nested && item) {
      if (nested.field === 'condition') {
        item = item.condition;
      } else {
        item = (item[nested.field] || [])[nested.index];
      }
      nested = nested.nested;
    }
    return item;
  }

  private updateItemAtPath(path: ItemPath, updatedItem: any): void {
    this.draft.update(d => {
      const newDraft = { ...d };
      const section = path.section;
      const newList = [...(d as any)[section]];
      if (!path.nested) {
        newList[path.index] = updatedItem;
      } else {
        newList[path.index] = this.deepUpdateNested({ ...newList[path.index] }, path.nested, updatedItem);
      }
      (newDraft as any)[section] = newList;
      return newDraft;
    });
  }

  private deepUpdateNested(parent: any, nested: NestedPath, updatedItem: any): any {
    const clone = { ...parent };
    if (!nested.nested) {
      if (nested.field === 'condition') {
        clone.condition = updatedItem;
      } else {
        const arr = [...(clone[nested.field] || [])];
        arr[nested.index] = updatedItem;
        clone[nested.field] = arr;
      }
    } else {
      if (nested.field === 'condition') {
        clone.condition = this.deepUpdateNested({ ...clone.condition }, nested.nested, updatedItem);
      } else {
        const arr = [...(clone[nested.field] || [])];
        arr[nested.index] = this.deepUpdateNested({ ...arr[nested.index] }, nested.nested, updatedItem);
        clone[nested.field] = arr;
      }
    }
    return clone;
  }

  private removeItemAtPath(path: ItemPath): void {
    this.draft.update(d => {
      const newDraft = { ...d };
      const section = path.section;
      if (!path.nested) {
        (newDraft as any)[section] = (d as any)[section].filter((_: any, idx: number) => idx !== path.index);
      } else {
        const newList = [...(d as any)[section]];
        newList[path.index] = this.deepRemoveNested({ ...newList[path.index] }, path.nested);
        (newDraft as any)[section] = newList;
      }
      return newDraft;
    });
  }

  private deepRemoveNested(parent: any, nested: NestedPath): any {
    const clone = { ...parent };
    if (!nested.nested) {
      if (nested.field === 'condition') {
        clone.condition = undefined;
      } else {
        clone[nested.field] = (clone[nested.field] || []).filter((_: any, idx: number) => idx !== nested.index);
      }
    } else {
      if (nested.field === 'condition') {
        clone.condition = this.deepRemoveNested({ ...clone.condition }, nested.nested);
      } else {
        const arr = [...(clone[nested.field] || [])];
        arr[nested.index] = this.deepRemoveNested({ ...arr[nested.index] }, nested.nested);
        clone[nested.field] = arr;
      }
    }
    return clone;
  }

  // --- Panel event handlers (triggers & conditions) ---
  onPanelItemChanged(item: any): void {
    const frame = this.currentFrame();
    if (!frame) return;
    this.updateItemAtPath(frame.path, item);
  }

  onPanelItemRemoved(): void {
    const frame = this.currentFrame();
    if (!frame) return;
    this.removeItemAtPath(frame.path);
    this.popPanel();
  }

  onEditNestedCondition(event: { field: string, index: number, label: string }): void {
    const frame = this.currentFrame();
    if (!frame) return;
    const nestedPath: NestedPath = { field: event.field as any, index: event.index };
    const newPath = this.appendNestedPath(frame.path, nestedPath);
    const item = this.resolveItemAtPath(newPath);
    const isGroup = item && (item.type === 'and' || item.type === 'or' ||
      (item.type === 'not' && item.condition &&
        (item.condition.type === 'and' || item.condition.type === 'or')));
    this.pushPanel(isGroup ? 'conditionGroup' : 'condition', newPath, event.label);
  }

  private appendNestedPath(basePath: ItemPath, append: NestedPath): ItemPath {
    const newPath = { ...basePath };
    if (!newPath.nested) {
      newPath.nested = append;
    } else {
      let current = { ...newPath.nested };
      newPath.nested = current;
      while (current.nested) {
        current.nested = { ...current.nested };
        current = current.nested;
      }
      current.nested = append;
    }
    return newPath;
  }

  // =============================================
  // Block nesting navigation
  // =============================================
  toggleBlockExpanded(blockId: string): void {
    if (this.reorderMode()) return;
    this.expandedBlockIds.update(ids => {
      const next = new Set(ids);
      if (next.has(blockId)) next.delete(blockId);
      else next.add(blockId);
      return next;
    });
  }

  pushNesting(blockIndex: number, field: string, label: string): void {
    const blocks = this.currentBlocks();
    const parent = blocks[blockIndex];
    if (!parent) return;

    this.nestingTransition.set('push');
    setTimeout(() => {
      this.nestingStack.update(s => [...s, {
        parentBlockId: parent._draftId,
        field: field as 'thenBlocks' | 'elseBlocks' | 'blocks',
        label,
      }]);
      this.expandedBlockIds.set(new Set());
      this.nestingTransition.set('none');
    }, 20);
  }

  popNesting(): void {
    this.nestingTransition.set('pop');
    setTimeout(() => {
      this.nestingStack.update(s => s.slice(0, -1));
      this.expandedBlockIds.set(new Set());
      this.nestingTransition.set('none');
    }, 20);
  }

  popToNestingLevel(level: number): void {
    this.nestingTransition.set('pop');
    setTimeout(() => {
      this.nestingStack.update(s => level < 0 ? [] : s.slice(0, level + 1));
      this.expandedBlockIds.set(new Set());
      this.nestingTransition.set('none');
    }, 20);
  }

  // =============================================
  // Block CRUD (operates on current nesting level)
  // =============================================

  /** Build a path to the current nesting level's block array */
  private currentBlocksPath(): { rootIndex: number; nestedFields: { field: string; blockId: string }[] } | null {
    const stack = this.nestingStack();
    if (stack.length === 0) return null;
    // Find root block index
    const first = stack[0];
    const rootIdx = this.draft().blocks.findIndex(b => b._draftId === first.parentBlockId);
    if (rootIdx < 0) return null;
    const fields = stack.map(f => ({ field: f.field, blockId: f.parentBlockId }));
    return { rootIndex: rootIdx, nestedFields: fields };
  }

  private updateCurrentBlockList(updater: (blocks: WorkflowBlockDraft[]) => WorkflowBlockDraft[]): void {
    const stack = this.nestingStack();
    if (stack.length === 0) {
      // Operating on root blocks
      this.draft.update(d => ({ ...d, blocks: updater(d.blocks) }));
      return;
    }

    // Deep update through nesting stack
    this.draft.update(d => {
      const newBlocks = [...d.blocks];
      let currentArr = newBlocks;
      const clones: { arr: WorkflowBlockDraft[]; idx: number; field: string }[] = [];

      for (const frame of stack) {
        const idx = currentArr.findIndex(b => b._draftId === frame.parentBlockId);
        if (idx < 0) return d;
        const clone = { ...currentArr[idx] };
        currentArr[idx] = clone;
        clones.push({ arr: currentArr, idx, field: frame.field });
        currentArr = [...((clone as any)[frame.field] || [])];
        (clone as any)[frame.field] = currentArr;
      }

      // Apply update to the innermost array
      const updated = updater(currentArr);
      if (clones.length > 0) {
        const last = clones[clones.length - 1];
        (last.arr[last.idx] as any)[last.field] = updated;
      }

      return { ...d, blocks: newBlocks };
    });
  }

  addBlockFromSheet(type: string): void {
    const b = newBlockDraft(type);
    this.updateCurrentBlockList(blocks => [...blocks, b]);
    // Auto-expand the new block
    this.expandedBlockIds.update(ids => {
      const next = new Set(ids);
      next.add(b._draftId);
      return next;
    });
  }

  updateCurrentBlock(i: number, b: WorkflowBlockDraft): void {
    this.updateCurrentBlockList(blocks => {
      const arr = [...blocks];
      arr[i] = b;
      return arr;
    });
  }

  removeCurrentBlock(i: number): void {
    this.updateCurrentBlockList(blocks => blocks.filter((_, idx) => idx !== i));
  }

  moveCurrentBlock(i: number, dir: -1 | 1): void {
    this.updateCurrentBlockList(blocks => {
      const arr = [...blocks];
      [arr[i], arr[i + dir]] = [arr[i + dir], arr[i]];
      return arr;
    });
  }

  onBlockDrop(event: CdkDragDrop<WorkflowBlockDraft[]>): void {
    if (event.previousIndex === event.currentIndex) return;
    this.updateCurrentBlockList(blocks => {
      const arr = [...blocks];
      moveItemInArray(arr, event.previousIndex, event.currentIndex);
      return arr;
    });
  }

  toggleReorderMode(): void {
    const next = !this.reorderMode();
    if (next) {
      this.expandedBlockIds.set(new Set());
    }
    this.reorderMode.set(next);
  }

  // =============================================
  // Lifecycle
  // =============================================
  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('workflowId');
    if (id) {
      this.isEditMode.set(true);
      this.workflowId.set(id);
      this.loadWorkflow(id);
    }
  }

  private loadWorkflow(id: string): void {
    this.isLoading.set(true);
    this.api.getWorkflow(id).subscribe({
      next: (wf) => {
        try {
          this.draft.set(definitionToDraft(wf));
          this.isLoading.set(false);
        } catch (e: any) {
          this.loadError.set(e?.message || 'Failed to parse workflow');
          this.isLoading.set(false);
        }
      },
      error: (err) => {
        this.loadError.set(err?.message || 'Failed to load workflow');
        this.isLoading.set(false);
      }
    });
  }

  // =============================================
  // Draft helpers
  // =============================================
  patchDraft(changes: Partial<WorkflowDraft>): void {
    this.draft.update(d => ({ ...d, ...changes }));
  }

  // --- Triggers ---
  addTrigger(): void {
    const t = newTriggerDraft();
    this.draft.update(d => ({ ...d, triggers: [...d.triggers, t] }));
    const idx = this.draft().triggers.length - 1;
    this.openPanel('trigger', 'triggers', idx, 'New Trigger');
  }

  removeTrigger(i: number): void {
    this.draft.update(d => ({ ...d, triggers: d.triggers.filter((_, idx) => idx !== i) }));
  }

  // --- Guard conditions ---
  readonly rootConditionGroup = computed(() => {
    const conds = this.draft().conditions;
    if (conds.length === 0) return null;
    const root = conds[0];
    if (root.type === 'and' || root.type === 'or') return root;
    if (root.type === 'not' && root.condition &&
        (root.condition.type === 'and' || root.condition.type === 'or')) return root;
    return null;
  });

  conditionChildCount(root: WorkflowConditionDraft): number {
    if (root.type === 'not' && root.condition) {
      return root.condition.conditions?.length || 0;
    }
    return root.conditions?.length || 0;
  }

  conditionGroupSummary(root: WorkflowConditionDraft): string {
    const count = this.conditionChildCount(root);
    if (count === 0) return 'No conditions defined';
    return `${count} condition${count !== 1 ? 's' : ''}`;
  }

  rootOperatorLabel(root: WorkflowConditionDraft): string {
    if (root.type === 'not') {
      const inner = root.condition;
      return `NOT ${(inner?.type || 'and').toUpperCase()}`;
    }
    return root.type.toUpperCase();
  }

  openConditionGroup(): void {
    if (this.draft().conditions.length === 0) {
      const root = newRootConditionGroup();
      this.draft.update(d => ({ ...d, conditions: [root] }));
    }
    this.openPanel('conditionGroup', 'conditions', 0, 'Guard Conditions');
  }

  // --- Tags ---
  addTagFromChipInput(event: MatChipInputEvent): void {
    const tag = (event.value || '').trim();
    if (tag && !this.draft().tags.includes(tag)) {
      this.draft.update(d => ({ ...d, tags: [...d.tags, tag] }));
    }
    event.chipInput.clear();
  }

  removeTag(tag: string): void {
    this.draft.update(d => ({ ...d, tags: d.tags.filter(t => t !== tag) }));
  }

  // --- Save ---
  save(): void {
    if (!this.isValid()) return;
    this.isSaving.set(true);
    this.saveError.set(null);

    const payload = draftToPayload(this.draft());
    const id = this.workflowId();
    const req = id
      ? this.api.updateWorkflowDefinition(id, payload)
      : this.api.createWorkflow(payload);

    req.subscribe({
      next: (wf) => {
        this.isSaving.set(false);
        this.router.navigate(['/workflows', wf.id, 'definition']);
      },
      error: (err) => {
        this.saveError.set(err?.message || 'Failed to save workflow');
        this.isSaving.set(false);
      }
    });
  }

  cancel(): void {
    if (this.isPanelOpen()) {
      this.closePanel();
      return;
    }
    if (this.nestingStack().length > 0) {
      this.popNesting();
      return;
    }
    if (window.history.length > 1) {
      this.location.back();
    } else {
      this.router.navigate(['/workflows']);
    }
  }

  patchName(e: Event): void {
    this.patchDraft({ name: (e.target as HTMLInputElement).value });
  }

  patchDescription(e: Event): void {
    this.patchDraft({ description: (e.target as HTMLTextAreaElement).value });
  }
}
