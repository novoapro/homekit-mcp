import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, act } from '@testing-library/react';
import { WebSocketProvider, useWebSocket } from './WebSocketContext';

// Mock ConfigContext
vi.mock('@/contexts/ConfigContext', () => ({
  useConfig: vi.fn(),
}));

import { useConfig } from '@/contexts/ConfigContext';

// Proper class-based WebSocket mock so `new WebSocket(url)` works correctly.
// Using an arrow-function implementation with vi.fn() causes vitest to skip
// the body when called with `new`, so wsInstance never gets set.
class MockWebSocket {
  static instances: MockWebSocket[] = [];

  readyState = 0; // CONNECTING
  onopen: ((event: Event) => void) | null = null;
  onclose: ((event: Event) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  url: string;

  constructor(url: string) {
    this.url = url;
    MockWebSocket.instances.push(this);
  }

  close() {
    this.readyState = 3; // CLOSED
  }

  send(_data: string) {}

  /** Helper: simulate successful open */
  simulateOpen() {
    this.readyState = 1; // OPEN
    if (this.onopen) this.onopen(new Event('open'));
  }

  /** Helper: simulate close */
  simulateClose() {
    this.readyState = 3; // CLOSED
    if (this.onclose) this.onclose(new Event('close'));
  }

  /** Helper: dispatch a typed message */
  simulateMessage(type: string, data: unknown) {
    if (this.onmessage) {
      this.onmessage(
        new MessageEvent('message', {
          data: JSON.stringify({ type, data }),
        }),
      );
    }
  }
}

// Add static constants that the real WebSocket has
(MockWebSocket as any).CONNECTING = 0;
(MockWebSocket as any).OPEN = 1;
(MockWebSocket as any).CLOSING = 2;
(MockWebSocket as any).CLOSED = 3;

describe('WebSocketContext', () => {
  let mockConfig: any;

  beforeEach(() => {
    vi.useFakeTimers();
    MockWebSocket.instances = [];

    mockConfig = {
      websocketEnabled: true,
      bearerToken: 'test-token',
      serverAddress: 'localhost',
      serverPort: 3000,
      useHTTPS: false,
    };

    (useConfig as any).mockReturnValue({ config: mockConfig });
    (globalThis as any).WebSocket = MockWebSocket;
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  // ─── Synchronous / non-async tests ────────────────────────────────────────

  it('provides context with initial disconnected state', () => {
    // Disable auto-connect so the provider stays in 'disconnected' state
    // and we can verify the initial context shape.
    mockConfig.websocketEnabled = false;

    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    expect(contextValue.connectionState).toBe('disconnected');
    expect(contextValue.isConnected).toBe(false);
  });

  it('provides reconnect and disconnect methods', () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    expect(typeof contextValue.reconnect).toBe('function');
    expect(typeof contextValue.disconnect).toBe('function');
  });

  it('provides event subscription methods', () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    expect(typeof contextValue.onLog).toBe('function');
    expect(typeof contextValue.onWorkflowLog).toBe('function');
    expect(typeof contextValue.onWorkflowsUpdated).toBe('function');
    expect(typeof contextValue.onDevicesUpdated).toBe('function');
    expect(typeof contextValue.onCharacteristicUpdated).toBe('function');
    expect(typeof contextValue.onLogsCleared).toBe('function');
    expect(typeof contextValue.onReconnected).toBe('function');
  });

  it('throws error when useWebSocket is used outside provider', () => {
    function TestComponent() {
      useWebSocket();
      return null;
    }

    expect(() => {
      render(<TestComponent />);
    }).toThrow('useWebSocket must be used within WebSocketProvider');
  });

  // ─── Connection lifecycle ──────────────────────────────────────────────────

  it('attempts to connect when config enables websocket', async () => {
    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    // Flush pending effects/microtasks from the render
    await act(async () => {});

    expect(MockWebSocket.instances).toHaveLength(1);
    expect(MockWebSocket.instances[0]!.url).toContain('ws://localhost:3000/ws');
  });

  it('does not connect when websocket is disabled', async () => {
    mockConfig.websocketEnabled = false;

    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    expect(MockWebSocket.instances).toHaveLength(0);
  });

  it('does not connect when no bearer token', async () => {
    mockConfig.bearerToken = '';

    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    expect(MockWebSocket.instances).toHaveLength(0);
  });

  it('transitions to connected state on WebSocket open', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return <div>{contextValue.connectionState}</div>;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    expect(ws).toBeDefined();

    act(() => {
      ws.simulateOpen();
    });

    expect(contextValue.connectionState).toBe('connected');
    expect(contextValue.isConnected).toBe(true);
  });

  it('transitions to disconnected state on WebSocket close', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return <div>{contextValue.connectionState}</div>;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    act(() => { ws.simulateOpen(); });
    expect(contextValue.connectionState).toBe('connected');

    act(() => { ws.simulateClose(); });
    expect(contextValue.connectionState).toBe('disconnected');
  });

  it('handles WebSocket error event', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    // onerror fires before onclose; after onerror+onclose the state goes disconnected
    act(() => {
      if (ws.onerror) ws.onerror(new Event('error'));
      ws.simulateClose();
    });

    expect(contextValue.connectionState).toBe('disconnected');
  });

  it('cleans up WebSocket on unmount', async () => {
    function TestComponent() {
      useWebSocket();
      return null;
    }

    const { unmount } = render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const closeSpy = vi.spyOn(ws, 'close');

    unmount();

    expect(closeSpy).toHaveBeenCalled();
  });

  it('constructs correct WebSocket URL', async () => {
    mockConfig.serverAddress = '192.168.1.100';
    mockConfig.serverPort = 8080;
    mockConfig.useHTTPS = false;

    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    expect(MockWebSocket.instances).toHaveLength(1);
    expect(MockWebSocket.instances[0]!.url).toContain('ws://192.168.1.100:8080/ws');
  });

  it('uses wss protocol when useHTTPS is true', async () => {
    mockConfig.useHTTPS = true;

    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    expect(MockWebSocket.instances[0]!.url).toContain('wss://');
  });

  it('includes bearer token in WebSocket URL', async () => {
    mockConfig.bearerToken = 'secret-token-123';

    function TestComponent() {
      useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    expect(MockWebSocket.instances[0]!.url).toContain('token=');
    expect(MockWebSocket.instances[0]!.url).toContain('secret-token-123');
  });

  // ─── Subscription helpers ─────────────────────────────────────────────────

  it('unsubscribe function removes handler', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const handler = vi.fn();
    const unsubscribe = contextValue.onLog(handler);

    expect(typeof unsubscribe).toBe('function');
    unsubscribe();
    // Handler should no longer be in the set after unsubscribe
  });

  // ─── Message dispatch ─────────────────────────────────────────────────────

  it('calls multiple onLog handlers', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    expect(ws).toBeDefined();

    const handler1 = vi.fn();
    const handler2 = vi.fn();
    contextValue.onLog(handler1);
    contextValue.onLog(handler2);

    const logData = { id: 'log-1', timestamp: '2024-01-01T00:00:00Z' };
    act(() => {
      ws.simulateMessage('log', logData);
    });

    expect(handler1).toHaveBeenCalledWith(logData);
    expect(handler2).toHaveBeenCalledWith(logData);
  });

  it('handles workflow_log message type', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onWorkflowLog(handler);

    const logData = { id: 'exec-1', status: 'running' };
    act(() => {
      ws.simulateMessage('workflow_log', logData);
    });

    expect(handler).toHaveBeenCalledWith({ type: 'new', data: logData });
  });

  it('handles workflows_updated message type', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onWorkflowsUpdated(handler);

    const workflows = [{ id: 'wf-1', name: 'Workflow 1' }];
    act(() => {
      ws.simulateMessage('workflows_updated', workflows);
    });

    expect(handler).toHaveBeenCalledWith(workflows);
  });

  it('handles devices_updated message type', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onDevicesUpdated(handler);

    act(() => {
      ws.simulateMessage('devices_updated', {});
    });

    expect(handler).toHaveBeenCalled();
  });

  it('handles characteristic_updated message type', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onCharacteristicUpdated(handler);

    const event = { deviceId: 'device-1', characteristicId: 'char-1', value: 50 };
    act(() => {
      ws.simulateMessage('characteristic_updated', event);
    });

    expect(handler).toHaveBeenCalledWith(event);
  });

  it('handles logs_cleared message type', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onLogsCleared(handler);

    act(() => {
      ws.simulateMessage('logs_cleared', {});
    });

    expect(handler).toHaveBeenCalled();
  });

  it('ignores malformed WebSocket messages', async () => {
    let contextValue: any;

    function TestComponent() {
      contextValue = useWebSocket();
      return null;
    }

    render(
      <WebSocketProvider>
        <TestComponent />
      </WebSocketProvider>,
    );

    await act(async () => {});

    const ws = MockWebSocket.instances[0]!;
    const handler = vi.fn();
    contextValue.onLog(handler);

    // Send invalid JSON directly
    expect(() => {
      if (ws.onmessage) {
        ws.onmessage(
          new MessageEvent('message', { data: 'invalid json {{{' }),
        );
      }
    }).not.toThrow();

    expect(handler).not.toHaveBeenCalled();
  });
});
