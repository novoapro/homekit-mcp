import { useMemo } from 'react';
import { Icon } from '@/components/Icon';
import { useDeviceRegistry } from '@/contexts/DeviceRegistryContext';
import type {
  WorkflowTriggerDef, DeviceStateTriggerDef,
  ScheduleTriggerDef, SunEventTriggerDef, WebhookTriggerDef,
} from '@/types/workflow-definition';
import { TRIGGER_TYPE_ICONS } from '@/types/workflow-log';
import { formatTriggerCondition, formatScheduleType, formatRetriggerPolicy } from '@/utils/workflow-definition-utils';
import './tree-common.css';

const DEPTH_COLORS = [
  'var(--depth-0)',
  'var(--depth-1)',
  'var(--depth-2)',
  'var(--depth-3)',
  'var(--depth-4)',
];

interface DefinitionTriggerProps {
  trigger: WorkflowTriggerDef;
  depth?: number;
}

export function DefinitionTrigger({ trigger, depth = 0 }: DefinitionTriggerProps) {
  const registry = useDeviceRegistry();
  const depthRange = Array.from({ length: depth }, (_, i) => i);

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
      <div className="tree-row">
        {depthRange.map(i => (
          <div
            key={i}
            className="connector-line"
            style={{ backgroundColor: DEPTH_COLORS[i % DEPTH_COLORS.length] }}
          />
        ))}

        <span className="tree-icon" style={{ color: 'var(--tint-main)' }}>
          <Icon name={triggerIcon} size={16} />
        </span>

        <div className="tree-info">
          <span className="tree-name">{displayName}</span>
          {detailText && <span className="tree-detail">{detailText}</span>}
          {retriggerLabel && (
            <span className="retrigger-badge">
              <span className="retrigger-badge-key">Retrigger</span>
              {retriggerLabel}
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
