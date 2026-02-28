import { Component, input, output } from '@angular/core';
import { IconComponent } from '../../../shared/components/icon.component';

const BLOCK_ICONS: Record<string, string> = {
  controlDevice: 'house', runScene: 'sparkles', webhook: 'link', log: 'doc-text',
  delay: 'clock', waitForState: 'clock', conditional: 'arrow-triangle-branch',
  repeat: 'arrow-2-squarepath', repeatWhile: 'arrow-2-squarepath',
  group: 'folder', stop: 'xmark-circle', executeWorkflow: 'arrow-right-circle',
};

const ACTION_TYPES = [
  { value: 'controlDevice', label: 'Control Device', desc: 'Set a device characteristic' },
  { value: 'runScene', label: 'Run Scene', desc: 'Trigger a HomeKit scene' },
  { value: 'webhook', label: 'Webhook', desc: 'Make an HTTP request' },
  { value: 'log', label: 'Log', desc: 'Write a log message' },
];

const FLOW_TYPES = [
  { value: 'delay', label: 'Delay', desc: 'Wait for a duration' },
  { value: 'waitForState', label: 'Wait for State', desc: 'Wait until a condition is met' },
  { value: 'conditional', label: 'If / Else', desc: 'Branch based on a condition' },
  { value: 'repeat', label: 'Repeat', desc: 'Run blocks N times' },
  { value: 'repeatWhile', label: 'Repeat While', desc: 'Loop while condition is true' },
  { value: 'group', label: 'Group', desc: 'Organize blocks together' },
  { value: 'stop', label: 'Stop', desc: 'Halt workflow execution' },
  { value: 'executeWorkflow', label: 'Call Workflow', desc: 'Run another workflow' },
];

@Component({
  selector: 'app-add-block-sheet',
  standalone: true,
  imports: [IconComponent],
  template: `
    @if (isOpen()) {
      <div class="sheet-backdrop" (click)="closed.emit()"></div>
      <div class="sheet-container">
        <div class="sheet-handle"></div>
        <h3 class="sheet-title">Add Block</h3>

        <div class="sheet-section">
          <span class="sheet-section-label">
            <span class="dot action"></span>
            Actions
          </span>
          @for (t of actionTypes; track t.value) {
            <button class="sheet-option" (click)="selected.emit(t.value); closed.emit()">
              <span class="sheet-option-icon action">
                <app-icon [name]="iconFor(t.value)" [size]="18" />
              </span>
              <div class="sheet-option-info">
                <span class="sheet-option-label">{{ t.label }}</span>
                <span class="sheet-option-desc">{{ t.desc }}</span>
              </div>
            </button>
          }
        </div>

        <div class="sheet-section">
          <span class="sheet-section-label">
            <span class="dot flow"></span>
            Flow Control
          </span>
          @for (t of flowTypes; track t.value) {
            <button class="sheet-option" (click)="selected.emit(t.value); closed.emit()">
              <span class="sheet-option-icon flow">
                <app-icon [name]="iconFor(t.value)" [size]="18" />
              </span>
              <div class="sheet-option-info">
                <span class="sheet-option-label">{{ t.label }}</span>
                <span class="sheet-option-desc">{{ t.desc }}</span>
              </div>
            </button>
          }
        </div>
      </div>
    }
  `,
  styles: [`
    .sheet-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(0, 0, 0, 0.35);
      z-index: 300;
      animation: sheetFadeIn 0.2s ease-out;
    }

    .sheet-container {
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      max-height: 75vh;
      background: var(--bg-card);
      border-radius: var(--radius-lg) var(--radius-lg) 0 0;
      box-shadow: 0 -8px 32px rgba(0, 0, 0, 0.15);
      z-index: 301;
      overflow-y: auto;
      padding: var(--spacing-sm) var(--spacing-md) calc(var(--spacing-xl) + env(safe-area-inset-bottom, 0));
      animation: sheetSlideUp 0.3s cubic-bezier(0.32, 0.72, 0, 1);
    }

    .sheet-handle {
      width: 36px;
      height: 4px;
      border-radius: 2px;
      background: color-mix(in srgb, var(--text-tertiary) 25%, transparent);
      margin: 0 auto var(--spacing-sm);
    }

    .sheet-title {
      font-size: var(--font-size-lg);
      font-weight: var(--font-weight-bold);
      color: var(--text-primary);
      margin: 0 0 var(--spacing-md);
      text-align: center;
    }

    .sheet-section {
      display: flex;
      flex-direction: column;
      gap: 2px;
      margin-bottom: var(--spacing-md);
    }

    .sheet-section-label {
      font-size: 10px;
      font-weight: var(--font-weight-black);
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: var(--text-tertiary);
      display: flex;
      align-items: center;
      gap: 6px;
      padding: var(--spacing-xs) 0;
    }

    .dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      flex-shrink: 0;
    }
    .dot.action { background: var(--tint-main); }
    .dot.flow { background: var(--color-workflow); }

    .sheet-option {
      display: flex;
      align-items: center;
      gap: var(--spacing-sm);
      padding: 10px 12px;
      border-radius: var(--radius-sm);
      background: none;
      border: none;
      cursor: pointer;
      font-family: inherit;
      text-align: left;
      width: 100%;
      transition: background var(--transition-fast);
      min-height: 44px;
    }
    .sheet-option:hover {
      background: var(--bg-detail);
    }
    .sheet-option:active {
      background: color-mix(in srgb, var(--bg-detail) 60%, var(--bg-pill));
      transform: scale(0.99);
    }

    .sheet-option-icon {
      width: 34px;
      height: 34px;
      border-radius: 50%;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }
    .sheet-option-icon.action {
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
      color: var(--tint-main);
    }
    .sheet-option-icon.flow {
      background: color-mix(in srgb, var(--color-workflow) 10%, transparent);
      color: var(--color-workflow);
    }

    .sheet-option-info {
      display: flex;
      flex-direction: column;
      gap: 1px;
      min-width: 0;
    }
    .sheet-option-label {
      font-size: var(--font-size-sm);
      font-weight: var(--font-weight-medium);
      color: var(--text-primary);
    }
    .sheet-option-desc {
      font-size: var(--font-size-xs);
      color: var(--text-tertiary);
    }

    @keyframes sheetFadeIn {
      from { opacity: 0; }
      to { opacity: 1; }
    }
    @keyframes sheetSlideUp {
      from { transform: translateY(100%); }
      to { transform: translateY(0); }
    }
  `]
})
export class AddBlockSheetComponent {
  isOpen = input.required<boolean>();
  selected = output<string>();
  closed = output<void>();

  readonly actionTypes = ACTION_TYPES;
  readonly flowTypes = FLOW_TYPES;

  iconFor(type: string): string { return BLOCK_ICONS[type] || 'square'; }
}
