import { Injectable, inject, signal, computed, DestroyRef } from '@angular/core';
import { Subject } from 'rxjs';
import { ConfigService } from './config.service';
import { StateChangeLog } from '../models/state-change-log.model';
import { WorkflowExecutionLog } from '../models/workflow-log.model';

export type WSConnectionState = 'disconnected' | 'connecting' | 'connected';

@Injectable({ providedIn: 'root' })
export class WebSocketService {
  private config = inject(ConfigService);
  private destroyRef = inject(DestroyRef);

  private ws: WebSocket | null = null;
  private reconnectTimer: any = null;
  private reconnectAttempts = 0;
  private readonly maxReconnectAttempts = 10;
  private readonly baseReconnectDelay = 1000;
  private readonly maxReconnectDelay = 30000;
  private intentionalClose = false;

  readonly connectionState = signal<WSConnectionState>('disconnected');
  readonly isConnected = computed(() => this.connectionState() === 'connected');

  readonly logMessage$ = new Subject<StateChangeLog>();
  readonly workflowLogMessage$ = new Subject<{ type: 'new' | 'updated'; data: WorkflowExecutionLog }>();
  readonly reconnected$ = new Subject<void>();

  constructor() {
    this.destroyRef.onDestroy(() => this.disconnect());
  }

  connect(): void {
    if (!this.config.websocketEnabled()) return;
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) return;
    if (!this.config.bearerToken()) return;

    this.intentionalClose = false;
    this.connectionState.set('connecting');

    const addr = this.config.serverAddress();
    const port = this.config.serverPort();
    const token = encodeURIComponent(this.config.bearerToken());
    const url = `ws://${addr}:${port}/ws?token=${token}`;

    try {
      this.ws = new WebSocket(url);
    } catch {
      this.connectionState.set('disconnected');
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.connectionState.set('connected');
      if (this.reconnectAttempts > 0) {
        this.reconnected$.next();
      }
      this.reconnectAttempts = 0;
    };

    this.ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        switch (msg.type) {
          case 'log':
            this.logMessage$.next(msg.data as StateChangeLog);
            break;
          case 'workflow_log':
            this.workflowLogMessage$.next({ type: 'new', data: msg.data as WorkflowExecutionLog });
            break;
          case 'workflow_log_updated':
            this.workflowLogMessage$.next({ type: 'updated', data: msg.data as WorkflowExecutionLog });
            break;
        }
      } catch {
        // Ignore malformed messages
      }
    };

    this.ws.onclose = () => {
      this.connectionState.set('disconnected');
      this.ws = null;
      if (!this.intentionalClose) {
        this.scheduleReconnect();
      }
    };

    this.ws.onerror = () => {
      // onclose fires after onerror, reconnect handled there
    };
  }

  disconnect(): void {
    this.intentionalClose = true;
    this.clearReconnectTimer();
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.connectionState.set('disconnected');
    this.reconnectAttempts = 0;
  }

  reconnect(): void {
    this.disconnect();
    if (this.config.websocketEnabled()) {
      setTimeout(() => this.connect(), 100);
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) return;
    if (!this.config.websocketEnabled()) return;

    this.clearReconnectTimer();

    const delay = Math.min(
      this.baseReconnectDelay * Math.pow(2, this.reconnectAttempts),
      this.maxReconnectDelay
    );

    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }
}
