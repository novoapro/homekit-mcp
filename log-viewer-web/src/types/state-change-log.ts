import type { WorkflowExecutionLog } from './workflow-log';

export type { WorkflowExecutionLog };

export enum LogCategory {
  StateChange = 'state_change',
  WebhookError = 'webhook_error',
  WebhookCall = 'webhook_call',
  ServerError = 'server_error',
  McpCall = 'mcp_call',
  RestCall = 'rest_call',
  WorkflowExecution = 'workflow_execution',
  WorkflowError = 'workflow_error',
  SceneExecution = 'scene_execution',
  SceneError = 'scene_error',
  BackupRestore = 'backup_restore',
}

export interface StateChangeLog {
  id: string;
  timestamp: string;
  deviceId: string;
  deviceName: string;
  roomName?: string;
  serviceId?: string;
  serviceName?: string;
  characteristicType: string;
  oldValue?: unknown;
  newValue?: unknown;
  category: LogCategory;
  errorDetails?: string;
  returnOutcome?: string;
  requestBody?: string;
  responseBody?: string;
  detailedRequestBody?: string;
  workflowExecution?: WorkflowExecutionLog;
}

export interface CategoryMeta {
  label: string;
  icon: string;
  color: string;
}

export const CATEGORY_META: Record<LogCategory, CategoryMeta> = {
  [LogCategory.StateChange]: { label: 'Device Update', icon: 'bolt-circle-fill', color: 'var(--color-state-change)' },
  [LogCategory.WebhookCall]: { label: 'Webhook Call', icon: 'paperplane-circle-fill', color: 'var(--color-webhook)' },
  [LogCategory.WebhookError]: { label: 'Webhook Error', icon: 'exclamation-circle-fill', color: 'var(--color-error)' },
  [LogCategory.McpCall]: { label: 'MCP Call', icon: 'arrows-circle-fill', color: 'var(--color-mcp)' },
  [LogCategory.RestCall]: { label: 'REST Call', icon: 'link-circle-fill', color: 'var(--color-rest)' },
  [LogCategory.ServerError]: { label: 'Server Error', icon: 'exclamation-circle-fill', color: 'var(--color-error)' },
  [LogCategory.WorkflowExecution]: { label: 'Workflow', icon: 'bolt-circle-fill', color: 'var(--color-workflow)' },
  [LogCategory.WorkflowError]: { label: 'Workflow Error', icon: 'exclamation-circle-fill', color: 'var(--color-error)' },
  [LogCategory.SceneExecution]: { label: 'Scene', icon: 'play-circle-fill', color: 'var(--color-scene)' },
  [LogCategory.SceneError]: { label: 'Scene Error', icon: 'exclamation-circle-fill', color: 'var(--color-error)' },
  [LogCategory.BackupRestore]: { label: 'Backup', icon: 'refresh-circle-fill', color: 'var(--color-backup)' },
};
