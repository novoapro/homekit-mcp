import { Component, input, output, inject, computed } from '@angular/core';
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

export function newBlockDraft(type: string): WorkflowBlockDraft {
  const base: WorkflowBlockDraft = {
    _draftId: newUUID(),
    block: ['controlDevice', 'runScene', 'webhook', 'log'].includes(type) ? 'action' : 'flowControl',
    type,
  };
  switch (type) {
    case 'controlDevice': base.value = true; break;
    case 'webhook': base.url = ''; base.method = 'POST'; break;
    case 'log': base.message = ''; break;
    case 'delay': base.seconds = 1; break;
    case 'waitForState': base.condition = newConditionDraft(); base.timeoutSeconds = 30; break;
    case 'conditional': base.condition = newConditionDraft(); base.thenBlocks = []; base.elseBlocks = []; break;
    case 'repeat': base.count = 1; base.blocks = []; break;
    case 'repeatWhile': base.condition = newConditionDraft(); base.blocks = []; base.maxIterations = 10; break;
    case 'group': base.label = ''; base.blocks = []; break;
    case 'stop': base.outcome = 'success'; break;
    case 'executeWorkflow': base.executionMode = 'async'; break;
  }
  return base;
}

const ACTION_TYPES = [
  { value: 'controlDevice', label: 'Control Device' },
  { value: 'runScene', label: 'Run Scene' },
  { value: 'webhook', label: 'Webhook' },
  { value: 'log', label: 'Log' },
];
const FLOW_TYPES = [
  { value: 'delay', label: 'Delay' },
  { value: 'waitForState', label: 'Wait for State' },
  { value: 'conditional', label: 'If / Else' },
  { value: 'repeat', label: 'Repeat' },
  { value: 'repeatWhile', label: 'Repeat While' },
  { value: 'group', label: 'Group' },
  { value: 'stop', label: 'Stop' },
  { value: 'executeWorkflow', label: 'Call Workflow' },
];
const BLOCK_TYPE_LABELS: Record<string, string> = {
  controlDevice: 'Control Device', runScene: 'Run Scene', webhook: 'Webhook', log: 'Log',
  delay: 'Delay', waitForState: 'Wait for State', conditional: 'If / Else',
  repeat: 'Repeat', repeatWhile: 'Repeat While', group: 'Group', stop: 'Stop',
  executeWorkflow: 'Execute Workflow',
};
const HTTP_METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
const OUTCOMES = [
  { value: 'success', label: 'Success' }, { value: 'failure', label: 'Failure' }, { value: 'skipped', label: 'Skipped' },
];
const EXEC_MODES = [
  { value: 'async', label: 'Async (fire & forget)' }, { value: 'sync', label: 'Sync (wait for completion)' },
];

const BLOCK_ICONS: Record<string, string> = {
  controlDevice: 'house', runScene: 'sparkles', webhook: 'link', log: 'doc-text',
  delay: 'clock', waitForState: 'clock', conditional: 'arrow-triangle-branch',
  repeat: 'arrow-2-squarepath', repeatWhile: 'arrow-2-squarepath',
  group: 'folder', stop: 'xmark-circle', executeWorkflow: 'arrow-right-circle',
};

@Component({
  selector: 'app-block-editor',
  standalone: true,
  imports: [BlockEditorComponent, DevicePickerComponent, ConditionEditorComponent, IconComponent,
            MatFormFieldModule, MatInputModule, MatSelectModule, MatButtonModule, MatIconModule],
  template: `
    <div class="block-editor">
      <!-- Header (hidden in panel mode) -->
      @if (!panelMode()) {
        <div class="block-header">
          <span class="block-type-badge" [class]="'badge-' + draft().block">
            {{ draft().block === 'action' ? 'Action' : 'Flow' }}
          </span>
          <div class="block-title-group">
            <span class="block-type-label">{{ autoDescription() }}</span>
          </div>
          <div class="block-actions">
            <button mat-icon-button [disabled]="isFirst()" (click)="movedUp.emit()" title="Move up" class="block-action-btn">
              <mat-icon>expand_less</mat-icon>
            </button>
            <button mat-icon-button [disabled]="isLast()" (click)="movedDown.emit()" title="Move down" class="block-action-btn">
              <mat-icon>expand_more</mat-icon>
            </button>
            <button mat-icon-button (click)="removed.emit()" title="Remove block" class="block-action-btn danger">
              <mat-icon>cancel</mat-icon>
            </button>
          </div>
        </div>
      }

      <!-- Optional label -->
      <mat-form-field appearance="fill">
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
          <mat-form-field appearance="fill">
            <mat-label>Value</mat-label>
            <input matInput [value]="valueStr()"
                   (change)="onValueChange($event)"
                   placeholder="e.g. true, false, 50" />
          </mat-form-field>
        }
        @case ('runScene') {
          <mat-form-field appearance="fill">
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
          <mat-form-field appearance="fill">
            <mat-label>URL</mat-label>
            <input matInput type="url" [value]="draft().url || ''"
                   (change)="patchUrl($event)"
                   placeholder="https://example.com/hook" />
          </mat-form-field>
          <mat-form-field appearance="fill">
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
          <mat-form-field appearance="fill">
            <mat-label>Message</mat-label>
            <textarea matInput [value]="draft().message || ''"
                      (change)="patchMessage($event)"
                      placeholder="Log message..." rows="2"></textarea>
          </mat-form-field>
        }
        @case ('delay') {
          <mat-form-field appearance="fill">
            <mat-label>Duration (seconds)</mat-label>
            <input matInput type="number" min="0" step="0.1"
                   [value]="draft().seconds ?? 1"
                   (change)="patchSeconds($event)" />
          </mat-form-field>
        }
        @case ('waitForState') {
          @if (draft().condition) {
            <div class="nested-section">
              <div class="nested-label">Condition to wait for</div>
              @if (panelMode()) {
                <div class="nested-summary-node" (click)="emitEditNestedCondition('condition', 0, conditionDesc(draft().condition!))">
                  <app-icon name="questionmark-circle" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ conditionDesc(draft().condition!) }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              } @else {
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              }
            </div>
          }
          <mat-form-field appearance="fill">
            <mat-label>Timeout (seconds)</mat-label>
            <input matInput type="number" min="1"
                   [value]="draft().timeoutSeconds ?? 30"
                   (change)="patchTimeout($event)" />
          </mat-form-field>
        }
        @case ('conditional') {
          @if (draft().condition) {
            <div class="nested-section">
              <div class="nested-label">If condition</div>
              @if (panelMode()) {
                <div class="nested-summary-node" (click)="emitEditNestedCondition('condition', 0, conditionDesc(draft().condition!))">
                  <app-icon name="questionmark-circle" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ conditionDesc(draft().condition!) }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              } @else {
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              }
            </div>
          }

          <!-- Then blocks -->
          <div class="nested-section">
            <div class="nested-label">Then <span class="nested-count">{{ (draft().thenBlocks || []).length }}</span></div>
            @if (panelMode()) {
              @for (b of draft().thenBlocks || []; track b._draftId; let i = $index) {
                <div class="nested-summary-node" (click)="emitEditNested('thenBlocks', i, nestedBlockDesc(b))">
                  <app-icon [name]="blockIconFor(b)" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ nestedBlockDesc(b) }}</span>
                  <span class="ns-badge" [class]="'nb-' + b.block">{{ b.block === 'action' ? 'A' : 'F' }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addThen(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addThen(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            } @else {
              @for (b of draft().thenBlocks || []; track b._draftId; let i = $index) {
                <div class="nested-block-item">
                  <app-block-editor [draft]="b"
                    [isFirst]="i === 0" [isLast]="i === (draft().thenBlocks || []).length - 1"
                    (changed)="updateThen(i, $event)" (removed)="removeThen(i)"
                    (movedUp)="moveThen(i, -1)" (movedDown)="moveThen(i, 1)" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addThen(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addThen(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            }
          </div>

          <!-- Else blocks -->
          <div class="nested-section">
            <div class="nested-label else-label">Else <span class="nested-count">{{ (draft().elseBlocks || []).length }}</span></div>
            @if (panelMode()) {
              @for (b of draft().elseBlocks || []; track b._draftId; let i = $index) {
                <div class="nested-summary-node" (click)="emitEditNested('elseBlocks', i, nestedBlockDesc(b))">
                  <app-icon [name]="blockIconFor(b)" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ nestedBlockDesc(b) }}</span>
                  <span class="ns-badge" [class]="'nb-' + b.block">{{ b.block === 'action' ? 'A' : 'F' }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addElse(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addElse(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            } @else {
              @for (b of draft().elseBlocks || []; track b._draftId; let i = $index) {
                <div class="nested-block-item">
                  <app-block-editor [draft]="b"
                    [isFirst]="i === 0" [isLast]="i === (draft().elseBlocks || []).length - 1"
                    (changed)="updateElse(i, $event)" (removed)="removeElse(i)"
                    (movedUp)="moveElse(i, -1)" (movedDown)="moveElse(i, 1)" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addElse(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addElse(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            }
          </div>
        }
        @case ('repeat') {
          <div class="field-row">
            <mat-form-field appearance="fill">
              <mat-label>Count</mat-label>
              <input matInput type="number" min="1" [value]="draft().count ?? 1"
                     (change)="patchCount($event)" />
            </mat-form-field>
            <mat-form-field appearance="fill">
              <mat-label>Delay between (sec)</mat-label>
              <input matInput type="number" min="0" step="0.1" [value]="draft().delayBetweenSeconds ?? 0"
                     (change)="patchDelay($event)" />
            </mat-form-field>
          </div>
          <div class="nested-section">
            <div class="nested-label">Blocks <span class="nested-count">{{ (draft().blocks || []).length }}</span></div>
            @if (panelMode()) {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-summary-node" (click)="emitEditNested('blocks', i, nestedBlockDesc(b))">
                  <app-icon [name]="blockIconFor(b)" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ nestedBlockDesc(b) }}</span>
                  <span class="ns-badge" [class]="'nb-' + b.block">{{ b.block === 'action' ? 'A' : 'F' }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            } @else {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-block-item">
                  <app-block-editor [draft]="b"
                    [isFirst]="i === 0" [isLast]="i === (draft().blocks || []).length - 1"
                    (changed)="updateBlocks(i, $event)" (removed)="removeBlock(i)"
                    (movedUp)="moveBlock(i, -1)" (movedDown)="moveBlock(i, 1)" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            }
          </div>
        }
        @case ('repeatWhile') {
          @if (draft().condition) {
            <div class="nested-section">
              <div class="nested-label">While condition</div>
              @if (panelMode()) {
                <div class="nested-summary-node" (click)="emitEditNestedCondition('condition', 0, conditionDesc(draft().condition!))">
                  <app-icon name="questionmark-circle" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ conditionDesc(draft().condition!) }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              } @else {
                <app-condition-editor [draft]="draft().condition!"
                  (changed)="patch({ condition: $event })" (removed)="patch({ condition: undefined })" />
              }
            </div>
          }
          <mat-form-field appearance="fill">
            <mat-label>Max iterations</mat-label>
            <input matInput type="number" min="1" [value]="draft().maxIterations ?? 10"
                   (change)="patchMaxIter($event)" />
          </mat-form-field>
          <div class="nested-section">
            <div class="nested-label">Blocks <span class="nested-count">{{ (draft().blocks || []).length }}</span></div>
            @if (panelMode()) {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-summary-node" (click)="emitEditNested('blocks', i, nestedBlockDesc(b))">
                  <app-icon [name]="blockIconFor(b)" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ nestedBlockDesc(b) }}</span>
                  <span class="ns-badge" [class]="'nb-' + b.block">{{ b.block === 'action' ? 'A' : 'F' }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            } @else {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-block-item">
                  <app-block-editor [draft]="b"
                    [isFirst]="i === 0" [isLast]="i === (draft().blocks || []).length - 1"
                    (changed)="updateBlocks(i, $event)" (removed)="removeBlock(i)"
                    (movedUp)="moveBlock(i, -1)" (movedDown)="moveBlock(i, 1)" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            }
          </div>
        }
        @case ('group') {
          <mat-form-field appearance="fill">
            <mat-label>Group Label</mat-label>
            <input matInput [value]="draft().label || ''"
                   (change)="patchLabel($event)"
                   placeholder="Group name" />
          </mat-form-field>
          <div class="nested-section">
            <div class="nested-label">Blocks <span class="nested-count">{{ (draft().blocks || []).length }}</span></div>
            @if (panelMode()) {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-summary-node" (click)="emitEditNested('blocks', i, nestedBlockDesc(b))">
                  <app-icon [name]="blockIconFor(b)" [size]="14" class="ns-icon" />
                  <span class="ns-name">{{ nestedBlockDesc(b) }}</span>
                  <span class="ns-badge" [class]="'nb-' + b.block">{{ b.block === 'action' ? 'A' : 'F' }}</span>
                  <app-icon name="chevron-down" [size]="11" class="ns-chevron" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            } @else {
              @for (b of draft().blocks || []; track b._draftId; let i = $index) {
                <div class="nested-block-item">
                  <app-block-editor [draft]="b"
                    [isFirst]="i === 0" [isLast]="i === (draft().blocks || []).length - 1"
                    (changed)="updateBlocks(i, $event)" (removed)="removeBlock(i)"
                    (movedUp)="moveBlock(i, -1)" (movedDown)="moveBlock(i, 1)" />
                </div>
              }
              <div class="nested-add-row">
                @for (t of actionTypes; track t.value) {
                  <button mat-stroked-button class="nested-add" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
                @for (t of flowTypes; track t.value) {
                  <button mat-stroked-button class="nested-add flow" (click)="addBlock(t.value)" type="button">{{ t.label }}</button>
                }
              </div>
            }
          </div>
        }
        @case ('stop') {
          <mat-form-field appearance="fill">
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
          <mat-form-field appearance="fill">
            <mat-label>Target Workflow ID</mat-label>
            <input matInput [value]="draft().targetWorkflowId || ''"
                   (change)="patchTargetId($event)"
                   placeholder="Workflow UUID" />
          </mat-form-field>
          <mat-form-field appearance="fill">
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
  `,
  styles: [`
    .block-editor { display: flex; flex-direction: column; gap: 2px; }
    .block-header { display: flex; align-items: center; gap: var(--spacing-sm); margin-bottom: var(--spacing-xs); }
    .block-type-badge {
      font-size: 9px; font-weight: var(--font-weight-bold); text-transform: uppercase;
      letter-spacing: 0.06em; padding: 2px 7px; border-radius: var(--radius-full); flex-shrink: 0;
    }
    .badge-action { background: color-mix(in srgb, var(--tint-main) 10%, transparent); color: var(--tint-main); }
    .badge-flowControl { background: color-mix(in srgb, var(--color-workflow) 10%, transparent); color: var(--color-workflow); }
    .block-title-group { flex: 1; min-width: 0; }
    .block-type-label { font-size: var(--font-size-sm); font-weight: var(--font-weight-medium); color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: block; }
    .block-actions { display: flex; align-items: center; gap: 2px; }
    .block-action-btn {
      --mdc-icon-button-icon-size: 18px;
      --mdc-icon-button-state-layer-size: 32px;
      --mdc-icon-button-icon-color: var(--text-tertiary);
      width: 32px; height: 32px;
    }
    .block-action-btn.danger {
      --mdc-icon-button-icon-color: var(--status-error);
      opacity: 0.6;
    }
    .block-action-btn.danger:hover { opacity: 1; }

    mat-form-field { width: 100%; }
    .field-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--spacing-sm); }

    .nested-section {
      border-left: 2px solid color-mix(in srgb, var(--tint-main) 12%, transparent);
      padding-left: var(--spacing-md); display: flex; flex-direction: column; gap: var(--spacing-sm);
      margin-top: var(--spacing-xs);
    }
    .nested-label {
      font-size: 10px; font-weight: var(--font-weight-semibold); color: var(--text-tertiary);
      letter-spacing: 0.04em; text-transform: uppercase;
      display: flex; align-items: center; gap: var(--spacing-xs);
    }
    .nested-count { font-weight: var(--font-weight-regular); opacity: 0.5; }
    .else-label { color: var(--status-running); }
    .nested-block-item { background: var(--bg-detail); border-radius: var(--radius-sm); padding: var(--spacing-sm); }

    /* Panel mode nested summary nodes */
    .nested-summary-node {
      display: flex; align-items: center; gap: var(--spacing-sm);
      padding: 10px 14px; border-radius: var(--radius-sm);
      background: var(--bg-detail); cursor: pointer;
      transition: all var(--transition-fast);
    }
    .nested-summary-node:hover { background: color-mix(in srgb, var(--bg-detail) 70%, var(--bg-pill)); }
    .nested-summary-node:active { transform: scale(0.99); }
    .ns-icon { color: var(--text-tertiary); flex-shrink: 0; opacity: 0.5; }
    .ns-name {
      flex: 1; font-size: var(--font-size-sm); font-weight: var(--font-weight-regular);
      color: var(--text-primary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .ns-badge {
      font-size: 8px; font-weight: var(--font-weight-semibold); padding: 2px 6px;
      border-radius: var(--radius-full); flex-shrink: 0;
    }
    .nb-action { background: color-mix(in srgb, var(--tint-main) 6%, transparent); color: var(--tint-main); }
    .nb-flowControl { background: color-mix(in srgb, var(--color-workflow) 6%, transparent); color: var(--color-workflow); }
    .ns-chevron { color: var(--text-tertiary); transform: rotate(-90deg); opacity: 0.25; flex-shrink: 0; }

    .nested-add-row { display: flex; flex-wrap: wrap; gap: 4px; }
    .nested-add {
      --mdc-outlined-button-label-text-size: 11px;
      --mdc-outlined-button-container-height: 28px;
      --mdc-outlined-button-label-text-color: var(--tint-main);
      --mdc-outlined-button-outline-color: color-mix(in srgb, var(--tint-main) 20%, transparent);
      min-width: auto;
      padding: 0 10px;
    }
    .nested-add.flow {
      --mdc-outlined-button-label-text-color: var(--color-workflow);
      --mdc-outlined-button-outline-color: color-mix(in srgb, var(--color-workflow) 20%, transparent);
    }
  `]
})
export class BlockEditorComponent {
  registry = inject(DeviceRegistryService);

  draft = input.required<WorkflowBlockDraft>();
  isFirst = input(false);
  isLast = input(false);
  panelMode = input(false);
  changed = output<WorkflowBlockDraft>();
  removed = output<void>();
  movedUp = output<void>();
  movedDown = output<void>();
  editNestedBlock = output<{ field: string, index: number, label: string }>();
  editNestedCondition = output<{ field: string, index: number, label: string }>();

  readonly actionTypes = ACTION_TYPES;
  readonly flowTypes = FLOW_TYPES;
  readonly httpMethods = HTTP_METHODS;
  readonly outcomes = OUTCOMES;
  readonly execModes = EXEC_MODES;

  readonly autoDescription = computed(() => {
    const d = this.draft();
    return d.name || blockAutoName(d, this.registry);
  });

  typeLabel(): string { return BLOCK_TYPE_LABELS[this.draft().type] || this.draft().type; }
  blockIconFor(b: WorkflowBlockDraft): string { return BLOCK_ICONS[b.type] || 'square'; }
  nestedBlockDesc(b: WorkflowBlockDraft): string { return b.name || blockAutoName(b, this.registry); }
  conditionDesc(c: WorkflowConditionDraft): string { return conditionAutoName(c, this.registry); }

  emitEditNested(field: string, index: number, label: string): void {
    this.editNestedBlock.emit({ field, index, label });
  }
  emitEditNestedCondition(field: string, index: number, label: string): void {
    this.editNestedCondition.emit({ field, index, label });
  }

  patch(changes: Partial<WorkflowBlockDraft>): void {
    this.changed.emit({ ...this.draft(), ...changes });
  }

  onDevicePicked(val: DevicePickerValue): void {
    this.patch({ deviceId: val.deviceId, serviceId: val.serviceId, characteristicId: val.characteristicId });
  }

  valueStr(): string {
    const v = this.draft().value;
    return v !== undefined ? String(v) : '';
  }

  onValueChange(event: Event): void {
    this.patch({ value: parseSmartValue((event.target as HTMLInputElement).value) });
  }

  patchName(e: Event): void { this.patch({ name: (e.target as HTMLInputElement).value || undefined }); }
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
  onSceneChange(value: string): void { this.patch({ sceneId: value }); }

  addThen(type: string): void { this.patch({ thenBlocks: [...(this.draft().thenBlocks || []), newBlockDraft(type)] }); }
  updateThen(i: number, b: WorkflowBlockDraft): void { const a = [...(this.draft().thenBlocks || [])]; a[i] = b; this.patch({ thenBlocks: a }); }
  removeThen(i: number): void { this.patch({ thenBlocks: (this.draft().thenBlocks || []).filter((_, idx) => idx !== i) }); }
  moveThen(i: number, dir: -1 | 1): void { const a = [...(this.draft().thenBlocks || [])]; [a[i], a[i + dir]] = [a[i + dir], a[i]]; this.patch({ thenBlocks: a }); }

  addElse(type: string): void { this.patch({ elseBlocks: [...(this.draft().elseBlocks || []), newBlockDraft(type)] }); }
  updateElse(i: number, b: WorkflowBlockDraft): void { const a = [...(this.draft().elseBlocks || [])]; a[i] = b; this.patch({ elseBlocks: a }); }
  removeElse(i: number): void { this.patch({ elseBlocks: (this.draft().elseBlocks || []).filter((_, idx) => idx !== i) }); }
  moveElse(i: number, dir: -1 | 1): void { const a = [...(this.draft().elseBlocks || [])]; [a[i], a[i + dir]] = [a[i + dir], a[i]]; this.patch({ elseBlocks: a }); }

  addBlock(type: string): void { this.patch({ blocks: [...(this.draft().blocks || []), newBlockDraft(type)] }); }
  updateBlocks(i: number, b: WorkflowBlockDraft): void { const a = [...(this.draft().blocks || [])]; a[i] = b; this.patch({ blocks: a }); }
  removeBlock(i: number): void { this.patch({ blocks: (this.draft().blocks || []).filter((_, idx) => idx !== i) }); }
  moveBlock(i: number, dir: -1 | 1): void { const a = [...(this.draft().blocks || [])]; [a[i], a[i + dir]] = [a[i + dir], a[i]]; this.patch({ blocks: a }); }
}
