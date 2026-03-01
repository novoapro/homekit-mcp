import type { ExecutionStatus } from '@/types/workflow-log';

const STATUS_CONFIG: Record<ExecutionStatus, { label: string; color: string }> = {
  running: { label: 'Running', color: 'var(--status-running)' },
  success: { label: 'Success', color: 'var(--status-active)' },
  failure: { label: 'Failed', color: 'var(--status-error)' },
  skipped: { label: 'Skipped', color: 'var(--status-inactive)' },
  conditionNotMet: { label: 'Condition Not Met', color: 'var(--status-warning)' },
  cancelled: { label: 'Cancelled', color: 'var(--status-inactive)' },
};

interface StatusBadgeProps {
  status: ExecutionStatus;
}

export function StatusBadge({ status }: StatusBadgeProps) {
  const config = STATUS_CONFIG[status] ?? { label: status, color: 'var(--text-secondary)' };
  const bgColor = `color-mix(in srgb, ${config.color} 15%, transparent)`;

  return (
    <span
      className="inline-flex items-center gap-1 whitespace-nowrap uppercase"
      style={{
        backgroundColor: bgColor,
        color: config.color,
        padding: '2px 8px',
        borderRadius: 'var(--radius-full)',
        fontSize: '10px',
        fontWeight: 'var(--font-weight-bold)',
        letterSpacing: '0.03em',
        lineHeight: '1.4',
      }}
    >
      {status === 'running' && (
        <span
          className="animate-pulse-custom"
          style={{
            width: 6,
            height: 6,
            borderRadius: '50%',
            backgroundColor: 'currentColor',
          }}
        />
      )}
      {config.label}
    </span>
  );
}
