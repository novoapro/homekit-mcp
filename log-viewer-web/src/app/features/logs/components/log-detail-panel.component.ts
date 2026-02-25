import { Component, input, signal } from '@angular/core';
import { IconComponent } from '../../../shared/components/icon.component';

@Component({
  selector: 'app-log-detail-panel',
  standalone: true,
  imports: [IconComponent],
  template: `
    <div class="detail-panel">
      @if (requestBody()) {
        <div class="detail-section">
          <div class="detail-header">
            <span class="detail-label">Request</span>
            <button class="copy-btn" (click)="copyToClipboard(requestBody())">
              <app-icon name="copy" [size]="12" />
              <span>{{ copiedRequest() ? 'Copied!' : 'Copy' }}</span>
            </button>
          </div>
          <pre class="detail-body">{{ formatJson(requestBody()) }}</pre>
        </div>
      }
      @if (responseBody()) {
        <div class="detail-section">
          <div class="detail-header">
            <span class="detail-label">Response</span>
            <button class="copy-btn" (click)="copyToClipboard(responseBody(), true)">
              <app-icon name="copy" [size]="12" />
              <span>{{ copiedResponse() ? 'Copied!' : 'Copy' }}</span>
            </button>
          </div>
          <pre class="detail-body">{{ formatJson(responseBody()) }}</pre>
        </div>
      }
    </div>
  `,
  styles: [`
    .detail-panel {
      padding: var(--spacing-sm) var(--card-padding) var(--card-padding);
      background: var(--bg-card);
    }
    .detail-section {
      margin-bottom: var(--spacing-sm);
    }
    .detail-section:last-child {
      margin-bottom: 0;
    }
    .detail-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 4px;
    }
    .detail-label {
      font-size: 10px;
      font-weight: var(--font-weight-bold);
      color: var(--text-secondary);
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .copy-btn {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      font-size: var(--font-size-xs);
      color: var(--tint-main);
      cursor: pointer;
      padding: 2px 6px;
      border-radius: var(--radius-xs);
      transition: background var(--transition-fast);
    }
    .copy-btn:hover {
      background: color-mix(in srgb, var(--tint-main) 10%, transparent);
    }
    .detail-body {
      font-family: var(--font-mono);
      font-size: var(--font-size-xs);
      color: var(--text-secondary);
      background: var(--bg-code);
      border-radius: var(--radius-sm);
      padding: var(--spacing-sm);
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-all;
      max-height: 300px;
      overflow-y: auto;
      line-height: 1.5;
      margin: 0;
    }
  `]
})
export class LogDetailPanelComponent {
  requestBody = input('');
  responseBody = input('');

  copiedRequest = signal(false);
  copiedResponse = signal(false);

  formatJson(str: string): string {
    try {
      const parsed = JSON.parse(str);
      return JSON.stringify(parsed, null, 2);
    } catch {
      return str;
    }
  }

  copyToClipboard(text: string, isResponse = false): void {
    navigator.clipboard.writeText(text).then(() => {
      if (isResponse) {
        this.copiedResponse.set(true);
        setTimeout(() => this.copiedResponse.set(false), 1500);
      } else {
        this.copiedRequest.set(true);
        setTimeout(() => this.copiedRequest.set(false), 1500);
      }
    });
  }
}
