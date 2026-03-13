import { useMemo, useState, useCallback } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import { useConfig } from '@/contexts/ConfigContext';
import type {
  WorkflowTriggerDef, DeviceStateTriggerDef,
  ScheduleTriggerDef, SunEventTriggerDef, WebhookTriggerDef,
} from '@/types/workflow-definition';
import { TRIGGER_TYPE_ICONS } from '@/types/workflow-log';
import { formatTriggerCondition, formatScheduleType, formatRetriggerPolicy } from '@/utils/workflow-definition-utils';
import './tree-common.css';

interface DefinitionTriggerProps {
  trigger: WorkflowTriggerDef;
  depth?: number;
}

export function DefinitionTrigger({ trigger, depth = 0 }: DefinitionTriggerProps) {
  const registry = useDeviceRegistry();
  const { baseUrl } = useConfig();
  const [copied, setCopied] = useState(false);

  const copyUrl = useCallback((text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, []);

  const triggerIcon = TRIGGER_TYPE_ICONS[trigger.type] || 'bolt-circle-fill';

  const displayName = useMemo(() => {
    if (trigger.name) return trigger.name;
    switch (trigger.type) {
      case 'deviceStateChange': {
        const d = trigger as DeviceStateTriggerDef;
        return registry.lookupDevice(d.deviceId)?.name || d.deviceId;
      }
      case 'schedule': return 'Schedule';
      case 'webhook': return 'Webhook';
      case 'workflow': return 'Callable Trigger';
      case 'sunEvent': {
        const s = trigger as SunEventTriggerDef;
        return s.event === 'sunrise' ? 'Sunrise' : 'Sunset';
      }
      default: return (trigger as WorkflowTriggerDef).type;
    }
  }, [trigger, registry]);

  const detailText = useMemo(() => {
    switch (trigger.type) {
      case 'deviceStateChange': {
        const d = trigger as DeviceStateTriggerDef;
        const device = registry.lookupDevice(d.deviceId);
        const char = registry.lookupCharacteristic(d.deviceId, d.characteristicId);
        const charLabel = char?.name || d.characteristicId;
        const parts: string[] = [];
        if (device?.room) parts.push(device.room);
        parts.push(`${charLabel} ${formatTriggerCondition(d.condition)}`);
        return parts.join(' · ');
      }
      case 'schedule': {
        const s = trigger as ScheduleTriggerDef;
        return formatScheduleType(s.scheduleType);
      }
      case 'webhook': {
        const w = trigger as WebhookTriggerDef;
        return `Token: ${w.token}`;
      }
      case 'sunEvent': {
        const s = trigger as SunEventTriggerDef;
        if (s.offsetMinutes === 0) return undefined;
        const abs = Math.abs(s.offsetMinutes);
        const dir = s.offsetMinutes > 0 ? 'after' : 'before';
        return `${abs} min ${dir}`;
      }
      case 'workflow': return 'Can be triggered by other workflows';
      default: return undefined;
    }
  }, [trigger, registry]);

  const retriggerLabel = useMemo(() => {
    const policy = (trigger as { retriggerPolicy?: string }).retriggerPolicy;
    if (!policy) return null;
    return formatRetriggerPolicy(policy);
  }, [trigger]);

  return (
    <div className="tree-node">

      <div className="tree-row" style={{ paddingLeft: depth * 20 }}>
        <span className="tree-chevron-spacer" />
        <span className="tree-icon" style={{ color: 'var(--tint-main)' }}>
          <Icon name={triggerIcon} size={16} />
        </span>

        <div className="tree-info">
          <span className="tree-name">{displayName}</span>
        </div>
      </div>

      {detailText && (
        <div className="tree-trigger-details" style={{ paddingLeft: depth * 20 + 18, display: 'flex', alignItems: 'center', gap: 6 }}>
          <span className="tree-detail">{detailText}</span>
          {trigger.type === 'webhook' && (trigger as WebhookTriggerDef).token && (
            <button
              type="button"
              style={{ background: 'none', border: 'none', padding: 0, cursor: 'pointer', color: copied ? 'var(--status-active)' : 'var(--text-tertiary)', display: 'inline-flex', flexShrink: 0 }}
              onClick={() => copyUrl(`${baseUrl}/workflows/webhook/${(trigger as WebhookTriggerDef).token}`)}
              title="Copy webhook URL"
            >
              <Icon name={copied ? 'checkmark' : 'doc-on-doc'} size={16} />
            </button>
          )}
        </div>
      )}

      {(retriggerLabel || (trigger.conditions && trigger.conditions.length > 0)) && (
        <div style={{ paddingLeft: depth * 20 + 18, display: 'flex', flexWrap: 'wrap', gap: 4, marginTop: 2 }}>
          {retriggerLabel && (
            <span className="retrigger-badge">
              <Icon name="repeat" size={12} className="retrigger-badge-icon" />
              {retriggerLabel}
            </span>
          )}
          {trigger.conditions && trigger.conditions.length > 0 && (() => {
            const conds = trigger.conditions!;
            return (
              <span className="retrigger-badge" style={{ borderColor: 'var(--tint-secondary)', color: 'var(--tint-secondary)' }}>
                <Icon name="shield" size={12} className="retrigger-badge-icon" />
                {conds.length === 1 && conds[0]?.type === 'and'
                  ? `${(conds[0] as { conditions?: unknown[] }).conditions?.length ?? 0} condition(s)`
                  : `${conds.length} condition(s)`
                }
              </span>
            );
          })()}
        </div>
      )}
    </div>
  );
}
