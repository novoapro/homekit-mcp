import { Icon } from './Icon';

interface EmptyStateProps {
  icon?: string;
  title?: string;
  message?: string;
}

export function EmptyState({
  icon = 'bolt-circle-fill',
  title = 'No data',
  message = '',
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center text-center animate-card-enter" style={{ padding: 'var(--spacing-2xl) var(--spacing-lg)', minHeight: 300 }}>
      <div className="opacity-60" style={{ color: 'var(--text-tertiary)', marginBottom: 'var(--spacing-md)' }}>
        <Icon name={icon} size={48} />
      </div>
      <h3
        style={{
          fontSize: 'var(--font-size-xl)',
          fontWeight: 'var(--font-weight-bold)',
          color: 'var(--text-primary)',
          marginBottom: 'var(--spacing-xs)',
        }}
      >
        {title}
      </h3>
      {message && (
        <p style={{ fontSize: 'var(--font-size-sm)', color: 'var(--text-secondary)', maxWidth: 300, lineHeight: 1.5 }}>
          {message}
        </p>
      )}
    </div>
  );
}
