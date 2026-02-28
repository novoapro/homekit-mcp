import { Component, input, output, inject, computed, ElementRef, viewChild, afterNextRender } from '@angular/core';
import { WorkflowBlockDraft, WorkflowConditionDraft, newUUID } from '../workflow-editor.types';
import { DevicePickerComponent, DevicePickerValue } from './device-picker.component';
import { ConditionEditorComponent } from './condition-editor.component';
import { IconComponent } from '../../../shared/components/icon.component';
import { DeviceRegistryService } from '../../../core/services/device-registry.service';
import { blockAutoName, conditionAutoName, parseSmartValue } from '../workflow-editor-utils';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { MatSelectModule } from '@angular/material/select';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';

function newConditionDraft(): WorkflowConditionDraft {
  return { _draftId: newUUID(), type: 'deviceState', comparison: { type: 'equals', value: true } };
}

const BLOCK_ICONS: Record<string, string> = {
  controlDevice: 'house', runScene: 'sparkles', webhook: 'link', log: 'doc-text',
  delay: 'clock', waitForState: 'clock', conditional: 'arrow-triangle-branch',
  repeat: 'arrow-2-squarepath', repeatWhile: 'arrow-2-squarepath',
  group: 'folder', stop: 'xmark-circle', executeWorkflow: 'arrow-right-circle',
};

const BLOCK_TYPE_LABELS: Record<string, string> = {
  controlDevice: 'Control Device', runScene: 'Run Scene', webhook: 'Webhook', log: 'Log',
  delay: 'Delay', waitForState: 'Wait for State', conditional: 'If / Else',
  repeat: 'Repeat', repeatWhile: 'Repeat While', group: 'Group', stop: 'Stop',
  executeWorkflow: 'Execute Workflow',
};

const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
const OUTCOMES = [
  { value: 'success', label: 'Success' },
  { value: 'failure', label: 'Failure' },
  { value: 'skipped', label: 'Skipped' },
];
const EXEC_MODES = [
  { value: 'async', label: 'Async (fire & forget)' },
  { value: 'sync', label: 'Sync (wait for completion)' },
];

@Component({
  selector: 'app-expandable-block-card',
  standalone: true,
  imports: [
    IconComponent, DevicePickerComponent, ConditionEditorComponent,
    MatFormFieldModule, MatInputModule, MatSelectModule, MatButtonModule, MatIconModule,
  ],
  template: `
    <!-- Collapsed Header (always visible) -->
    <div class="card-header" [class.expanded]="isExpanded()" (click)="toggled.emit()">
      <span class="ordinal-badge" [class]="'ord-' + draft().block">{{ ordinal() }}</span>
      <span class="card-icon-wrap" [class]="draft().block">
        <app-icon [name]="icon()" [size]="15" class="card-icon" />
      </span>
      <div class="card-info">
        <span class="card-name">{{ autoName() }}</span>
        @if (!isExpanded() && childSummary()) {
          <span class="card-children">{{ childSummary() }}</span>
        }
      </div>
      <span class="card-type-badge" [class]="'tbadge-' + draft().block">
        {{ draft().block === 'action' ? 'Action' : 'Flow' }}
      </span>
      <app-icon [name]="isExpanded() ? 'chevron-down' : 'chevron-right'" [size]="12" class="card-chevron" />
    </div>

    <!-- Expanded Body -->
    @if (isExpanded()) {
      <div class="card-body">
        <!-- Actions row -->
        <div class="card-actions-bar">
          <button mat-icon-button [disabled]="isFirst()" (click)="movedUp.emit(); $event.stopPropagation()" title="Move up" class="card-action-btn">
            <mat-icon>expand_less</mat-icon>
          </button>
          <button mat-icon-button [disabled]="isLast()" (click)="movedDown.emit(); $event.stopPropagation()" title="Move down" class="card-action-btn">
            <mat-icon>expand_more</mat-icon>
          </button>
          <span class="card-type-label">{{ typeLabel() }}</span>
          <span class="flex-spacer"></span>
          <button mat-icon-button (click)="removed.emit(); $event.stopPropagation()" title="Remove" class="card-action-btn danger">
            <mat-icon>delete_outline</mat-icon>
          </button>
        </div>

        <!-- Optional label -->
        <mat-form-field appearance="fill" subscriptSizing="dynamic">
          <mat-label>Label (optional)</mat-label>
          <input matInput [value]="draft().name || ''"
                 (change)="patchName($event)"
                 placeholder="Human-readable label" />
        </mat-form-field>

        <!-- Per-type fields -->
        @switch (draft().type) {
          @case ('controlDevice') {
            <app-device-picker
              [initialDeviceId]="draft().deviceId"
              [initialServiceId]="draft().serviceId"
              [initialCharId]="draft().characteristicId"
              (changed)="onDevicePicked($event)"
            />
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Value</mat-label>
              <input matInput [value]="valueStr()"
                     (change)="onValueChange($event)"
                     placeholder="e.g. true, false, 50" />
            </mat-form-field>
          }
          @case ('runScene') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Scene</mat-label>
              <mat-select [value]="draft().sceneId || ''"
                          (selectionChange)="onSceneChange($event.value)">
                <mat-option value="">-- Select scene --</mat-option>
                @for (scene of registry.scenes(); track scene.id) {
                  <mat-option [value]="scene.id">{{ scene.name }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
          @case ('webhook') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>URL</mat-label>
              <input matInput type="url" [value]="draft().url || ''"
                     (change)="patchUrl($event)"
                     placeholder="https://example.com/hook" />
            </mat-form-field>
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Method</mat-label>
              <mat-select [value]="draft().method || 'POST'"
                          (selectionChange)="patchMethod($event.value)">
                @for (m of httpMethods; track m) {
                  <mat-option [value]="m">{{ m }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
          @case ('log') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Message</mat-label>
              <textarea matInput [value]="draft().message || ''"
                        (change)="patchMessage($event)"
                        placeholder="Log message..." rows="2"></textarea>
            </mat-form-field>
          }
          @case ('delay') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Duration (seconds)</mat-label>
              <input matInput type="number" min="0" step="0.1"
                     [value]="draft().seconds ?? 1"
                     (change)="patchSeconds($event)" />
            </mat-form-field>
          }
          @case ('waitForState') {
            @if (draft().condition) {
              <div class="inline-condition">
                <div class="inline-condition-label">Condition to wait for</div>
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              </div>
            }
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Timeout (seconds)</mat-label>
              <input matInput type="number" min="1"
                     [value]="draft().timeoutSeconds ?? 30"
                     (change)="patchTimeout($event)" />
            </mat-form-field>
          }
          @case ('conditional') {
            @if (draft().condition) {
              <div class="inline-condition">
                <div class="inline-condition-label">If condition</div>
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              </div>
            }
            <!-- Then blocks nav -->
            <button class="nested-nav-btn" (click)="navigateToNested.emit({ field: 'thenBlocks', label: 'Then Blocks' }); $event.stopPropagation()">
              <span class="nested-nav-icon then">
                <app-icon name="checkmark-circle" [size]="14" />
              </span>
              <span class="nested-nav-text">Then Blocks</span>
              <span class="nested-nav-count">{{ (draft().thenBlocks || []).length }}</span>
              <app-icon name="chevron-right" [size]="12" class="nested-nav-chevron" />
            </button>
            <!-- Else blocks nav -->
            <button class="nested-nav-btn else" (click)="navigateToNested.emit({ field: 'elseBlocks', label: 'Else Blocks' }); $event.stopPropagation()">
              <span class="nested-nav-icon else">
                <app-icon name="xmark-circle" [size]="14" />
              </span>
              <span class="nested-nav-text">Else Blocks</span>
              <span class="nested-nav-count">{{ (draft().elseBlocks || []).length }}</span>
              <app-icon name="chevron-right" [size]="12" class="nested-nav-chevron" />
            </button>
          }
          @case ('repeat') {
            <div class="field-row">
              <mat-form-field appearance="fill" subscriptSizing="dynamic">
                <mat-label>Count</mat-label>
                <input matInput type="number" min="1" [value]="draft().count ?? 1"
                       (change)="patchCount($event)" />
              </mat-form-field>
              <mat-form-field appearance="fill" subscriptSizing="dynamic">
                <mat-label>Delay between (sec)</mat-label>
                <input matInput type="number" min="0" step="0.1" [value]="draft().delayBetweenSeconds ?? 0"
                       (change)="patchDelay($event)" />
              </mat-form-field>
            </div>
            <button class="nested-nav-btn" (click)="navigateToNested.emit({ field: 'blocks', label: 'Repeat Blocks' }); $event.stopPropagation()">
              <span class="nested-nav-icon">
                <app-icon name="arrow-2-squarepath" [size]="14" />
              </span>
              <span class="nested-nav-text">Repeat Blocks</span>
              <span class="nested-nav-count">{{ (draft().blocks || []).length }}</span>
              <app-icon name="chevron-right" [size]="12" class="nested-nav-chevron" />
            </button>
          }
          @case ('repeatWhile') {
            @if (draft().condition) {
              <div class="inline-condition">
                <div class="inline-condition-label">While condition</div>
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              </div>
            }
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Max iterations</mat-label>
              <input matInput type="number" min="1" [value]="draft().maxIterations ?? 10"
                     (change)="patchMaxIter($event)" />
            </mat-form-field>
            <button class="nested-nav-btn" (click)="navigateToNested.emit({ field: 'blocks', label: 'Loop Blocks' }); $event.stopPropagation()">
              <span class="nested-nav-icon">
                <app-icon name="arrow-2-squarepath" [size]="14" />
              </span>
              <span class="nested-nav-text">Loop Blocks</span>
              <span class="nested-nav-count">{{ (draft().blocks || []).length }}</span>
              <app-icon name="chevron-right" [size]="12" class="nested-nav-chevron" />
            </button>
          }
          @case ('group') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Group Label</mat-label>
              <input matInput [value]="draft().label || ''"
                     (change)="patchLabel($event)"
                     placeholder="Group name" />
            </mat-form-field>
            <button class="nested-nav-btn" (click)="navigateToNested.emit({ field: 'blocks', label: 'Group Blocks' }); $event.stopPropagation()">
              <span class="nested-nav-icon">
                <app-icon name="folder" [size]="14" />
              </span>
              <span class="nested-nav-text">Group Blocks</span>
              <span class="nested-nav-count">{{ (draft().blocks || []).length }}</span>
              <app-icon name="chevron-right" [size]="12" class="nested-nav-chevron" />
            </button>
          }
          @case ('stop') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Outcome</mat-label>
              <mat-select [value]="draft().outcome || 'success'"
                          (selectionChange)="patchOutcome($event.value)">
                @for (o of outcomes; track o.value) {
                  <mat-option [value]="o.value">{{ o.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
          @case ('executeWorkflow') {
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Target Workflow ID</mat-label>
              <input matInput [value]="draft().targetWorkflowId || ''"
                     (change)="patchTargetId($event)"
                     placeholder="Workflow UUID" />
            </mat-form-field>
            <mat-form-field appearance="fill" subscriptSizing="dynamic">
              <mat-label>Execution Mode</mat-label>
              <mat-select [value]="draft().executionMode || 'async'"
                          (selectionChange)="patchExecMode($event.value)">
                @for (m of execModes; track m.value) {
                  <mat-option [value]="m.value">{{ m.label }}</mat-option>
                }
              </mat-select>
            </mat-form-field>
          }
        }
      </div>
    }
  `,
  styles: [`
    :host {
      display: block;
      border-radius: var(--radius-sm);
      overflow: hidden;
      transition: box-shadow var(--transition-fast);
    }

    /* === Header (collapsed row) === */
    .card-header {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: 10px 14px;
      cursor: pointer;
      background: var(--bg-detail);
      border-left: 3px solid transparent;
      transition: background var(--transition-fast), border-color var(--transition-fast);
      min-height: 44px;
    }
    :host:has(.card-header.expanded) {
      box-shadow: var(--shadow-card);
    }
    .card-header:hover {
      background: color-mix(in srgb, var(--bg-detail) 60%, var(--bg-pill));
    }
    .card-header:active {
      transform: scale(0.995);
    }
    :host-context(.accent-action) .card-header,
    :host(.accent-action) .card-header {
      border-left-color: var(--tint-main);
    }
    :host-context(.accent-flow) .card-header,
    :host(.accent-flow) .card-header {
      border-left-color: var(--color-workflow);
    }
    /* Use block type from draft */
    .card-header { border-left-color: var(--tint-main); }
    :host([data-block="flowControl"]) .card-header { border-left-color: var(--color-workflow); }

    /* Ordinal */
    .ordinal-badge {
      font-size: 10px;
      font-weight: var(--font-weight-bold);
      font-variant-numeric: tabular-nums;
      min-width: 20px;
      height: 20px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: var(--radius-xs);
      flex-shrink: 0;
    }
    .ord-action {
      background: color-mix(in srgb, var(--tint-main) 15%, transparent);
      color: var(--tint-main);
    }
    .ord-flowControl {
      background: color-mix(in srgb, var(--color-workflow) 15%, transparent);
      color: var(--color-workflow);
    }

    /* Icon wrap */
    .card-icon-wrap {
      width: 30px;
      height: 30px;
      border-radius: 50%;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .card-icon-wrap.action {
      background: color-mix(in srgb, var(--tint-main) 12%, transparent);
    }
    .card-icon-wrap.action .card-icon { color: var(--tint-main); }
    .card-icon-wrap.flowControl {
      background: color-mix(in srgb, var(--color-workflow) 12%, transparent);
    }
    .card-icon-wrap.flowControl .card-icon { color: var(--color-workflow); }

    /* Info */
    .card-info {
      flex: 1;
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 2px;
    }
    .card-name {
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-medium);
      color: var(--text-primary);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .card-children {
      font-size: 10px;
      color: var(--text-tertiary);
    }

    /* Type badge */
    .card-type-badge {
      font-size: 9px;
      font-weight: var(--font-weight-semibold);
      text-transform: uppercase;
      letter-spacing: 0.04em;
      padding: 2px 7px;
      border-radius: var(--radius-full);
      flex-shrink: 0;
    }
    .tbadge-action {
      background: color-mix(in srgb, var(--tint-main) 12%, transparent);
      color: var(--tint-main);
    }
    .tbadge-flowControl {
      background: color-mix(in srgb, var(--color-workflow) 12%, transparent);
      color: var(--color-workflow);
    }

    /* Chevron */
    .card-chevron {
      color: var(--text-tertiary);
      opacity: 0.3;
      flex-shrink: 0;
      transition: transform var(--transition-fast), opacity var(--transition-fast);
    }
    .card-header:hover .card-chevron { opacity: 0.6; }

    /* === Body (expanded area) === */
    .card-body {
      display: flex;
      flex-direction: column;
      gap: 4px;
      padding: var(--spacing-sm) var(--spacing-md) var(--spacing-md);
      background: var(--bg-card);
      border-top: 1px solid var(--border-color);
      animation: expandIn 0.2s ease-out;
    }
    @keyframes expandIn {
      from { opacity: 0; transform: translateY(-4px); }
      to { opacity: 1; transform: translateY(0); }
    }

    /* Actions bar */
    .card-actions-bar {
      display: flex;
      align-items: center;
      gap: 2px;
      margin-bottom: 2px;
    }
    .card-action-btn {
      --mdc-icon-button-icon-size: 18px;
      --mdc-icon-button-state-layer-size: 32px;
      --mdc-icon-button-icon-color: var(--text-tertiary);
      width: 32px !important;
      height: 32px !important;
    }
    .card-action-btn.danger {
      --mdc-icon-button-icon-color: var(--status-error);
      opacity: 0.5;
    }
    .card-action-btn.danger:hover { opacity: 1; }
    .card-type-label {
      font-size: 10px;
      font-weight: var(--font-weight-bold);
      color: var(--text-tertiary);
      text-transform: uppercase;
      letter-spacing: 0.06em;
    }
    .flex-spacer { flex: 1; }

    mat-form-field { width: 100%; }
    .field-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--spacing-sm); }

    /* Inline condition */
    .inline-condition {
      border-left: 2px solid color-mix(in srgb, var(--tint-secondary) 25%, transparent);
      padding-left: var(--spacing-md);
      display: flex;
      flex-direction: column;
      gap: var(--spacing-xs);
    }
    .inline-condition-label {
      font-size: 10px;
      font-weight: var(--font-weight-semibold);
      color: var(--text-tertiary);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    /* === Nested navigation buttons === */
    .nested-nav-btn {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: 12px 14px;
      border-radius: var(--radius-sm);
      background: var(--bg-detail);
      border: 1px solid color-mix(in srgb, var(--border-color) 60%, transparent);
      cursor: pointer;
      transition: all var(--transition-fast);
      font-family: inherit;
      width: 100%;
      text-align: left;
    }
    .nested-nav-btn:hover {
      background: color-mix(in srgb, var(--bg-detail) 60%, var(--bg-pill));
      border-color: var(--border-color);
    }
    .nested-nav-btn:active { transform: scale(0.99); }

    .nested-nav-icon {
      width: 26px;
      height: 26px;
      border-radius: 50%;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
      color: var(--tint-main);
    }
    .nested-nav-icon.then {
      background: color-mix(in srgb, var(--status-active) 10%, transparent);
      color: var(--status-active);
    }
    .nested-nav-icon.else {
      background: color-mix(in srgb, var(--status-running) 10%, transparent);
      color: var(--status-running);
    }

    .nested-nav-text {
      flex: 1;
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-medium);
      color: var(--text-primary);
    }
    .nested-nav-count {
      font-size: 11px;
      font-weight: var(--font-weight-semibold);
      color: var(--text-tertiary);
      background: var(--bg-pill);
      padding: 1px 8px;
      border-radius: var(--radius-full);
      min-width: 22px;
      text-align: center;
    }
    .nested-nav-chevron {
      color: var(--text-tertiary);
      opacity: 0.4;
      flex-shrink: 0;
    }
  `],
  host: {
    '[attr.data-block]': 'draft().block',
    '[style.--card-accent]': "draft().block === 'action' ? 'var(--tint-main)' : 'var(--color-workflow)'"
  }
})
export class ExpandableBlockCardComponent {
  registry = inject(DeviceRegistryService);

  draft = input.required<WorkflowBlockDraft>();
  ordinal = input.required<number>();
  isFirst = input(false);
  isLast = input(false);
  isExpanded = input(false);

  changed = output<WorkflowBlockDraft>();
  removed = output<void>();
  movedUp = output<void>();
  movedDown = output<void>();
  toggled = output<void>();
  navigateToNested = output<{ field: string; label: string }>();

  readonly httpMethods = HTTP_METHODS;
  readonly outcomes = OUTCOMES;
  readonly execModes = EXEC_MODES;

  readonly icon = computed(() => BLOCK_ICONS[this.draft().type] || 'square');
  readonly autoName = computed(() => this.draft().name || blockAutoName(this.draft(), this.registry));

  typeLabel(): string { return BLOCK_TYPE_LABELS[this.draft().type] || this.draft().type; }

  childSummary(): string | null {
    const b = this.draft();
    if (b.type === 'conditional') {
      const t = b.thenBlocks?.length || 0;
      const e = b.elseBlocks?.length || 0;
      if (t + e === 0) return null;
      const parts: string[] = [];
      if (t > 0) parts.push(`${t} then`);
      if (e > 0) parts.push(`${e} else`);
      return parts.join(', ');
    }
    if (['repeat', 'repeatWhile', 'group'].includes(b.type)) {
      const c = b.blocks?.length || 0;
      return c > 0 ? `${c} block${c > 1 ? 's' : ''}` : null;
    }
    return null;
  }

  valueStr(): string {
    const v = this.draft().value;
    return v !== undefined ? String(v) : '';
  }

  conditionDesc(c: WorkflowConditionDraft): string { return conditionAutoName(c, this.registry); }

  // --- Patch helpers ---
  patch(changes: Partial<WorkflowBlockDraft>): void {
    this.changed.emit({ ...this.draft(), ...changes });
  }

  patchName(e: Event): void { this.patch({ name: (e.target as HTMLInputElement).value || undefined }); }
  onDevicePicked(val: DevicePickerValue): void { this.patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId }); }
  onValueChange(e: Event): void { this.patch({ value: parseSmartValue((e.target as HTMLInputElement).value) }); }
  onSceneChange(value: string): void { this.patch({ sceneId: value }); }
  patchUrl(e: Event): void { this.patch({ url: (e.target as HTMLInputElement).value }); }
  patchMethod(value: string): void { this.patch({ method: value }); }
  patchMessage(e: Event): void { this.patch({ message: (e.target as HTMLTextAreaElement).value }); }
  patchSeconds(e: Event): void { this.patch({ seconds: +(e.target as HTMLInputElement).value }); }
  patchTimeout(e: Event): void { this.patch({ timeoutSeconds: +(e.target as HTMLInputElement).value }); }
  patchCount(e: Event): void { this.patch({ count: +(e.target as HTMLInputElement).value }); }
  patchDelay(e: Event): void { this.patch({ delayBetweenSeconds: +(e.target as HTMLInputElement).value }); }
  patchMaxIter(e: Event): void { this.patch({ maxIterations: +(e.target as HTMLInputElement).value }); }
  patchLabel(e: Event): void { this.patch({ label: (e.target as HTMLInputElement).value }); }
  patchOutcome(value: string): void { this.patch({ outcome: value }); }
  patchTargetId(e: Event): void { this.patch({ targetWorkflowId: (e.target as HTMLInputElement).value }); }
  patchExecMode(value: string): void { this.patch({ executionMode: value }); }
}
