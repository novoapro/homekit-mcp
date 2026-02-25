import { Injectable, signal, computed } from '@angular/core';

const STORAGE_PREFIX = 'hk-log-viewer';

@Injectable({ providedIn: 'root' })
export class ConfigService {
  readonly serverAddress = signal('localhost');
  readonly serverPort = signal(3000);
  readonly bearerToken = signal('');
  readonly pollingInterval = signal(10); // seconds, 0 = disabled
  readonly websocketEnabled = signal(true);

  readonly isConfigured = computed(() => !!this.bearerToken());

  readonly baseUrl = computed(() => {
    return `http://${this.serverAddress()}:${this.serverPort()}`;
  });

  constructor() {
    this.load();
  }

  private load(): void {
    const addr = localStorage.getItem(`${STORAGE_PREFIX}:serverAddress`);
    const port = localStorage.getItem(`${STORAGE_PREFIX}:serverPort`);
    const token = localStorage.getItem(`${STORAGE_PREFIX}:bearerToken`);
    const interval = localStorage.getItem(`${STORAGE_PREFIX}:pollingInterval`);

    if (addr) this.serverAddress.set(addr);
    if (port) this.serverPort.set(Number(port));
    if (token) this.bearerToken.set(token);
    if (interval !== null) this.pollingInterval.set(Number(interval));

    const wsEnabled = localStorage.getItem(`${STORAGE_PREFIX}:websocketEnabled`);
    if (wsEnabled !== null) this.websocketEnabled.set(wsEnabled === 'true');
  }

  save(): void {
    localStorage.setItem(`${STORAGE_PREFIX}:serverAddress`, this.serverAddress());
    localStorage.setItem(`${STORAGE_PREFIX}:serverPort`, String(this.serverPort()));
    localStorage.setItem(`${STORAGE_PREFIX}:bearerToken`, this.bearerToken());
    localStorage.setItem(`${STORAGE_PREFIX}:pollingInterval`, String(this.pollingInterval()));
    localStorage.setItem(`${STORAGE_PREFIX}:websocketEnabled`, String(this.websocketEnabled()));
  }
}
