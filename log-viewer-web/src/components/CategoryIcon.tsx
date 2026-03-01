import { Icon } from './Icon';
import { type LogCategory, CATEGORY_META } from '@/types/state-change-log';

interface CategoryIconProps {
  category: LogCategory;
  size?: number;
}

export function CategoryIcon({ category, size = 32 }: CategoryIconProps) {
  const meta = CATEGORY_META[category];
  const color = meta?.color ?? 'var(--tint-main)';
  const iconName = meta?.icon ?? 'bolt-circle-fill';

  return (
    <div
      className="flex items-center justify-center shrink-0"
      style={{
        width: size,
        height: size,
        borderRadius: 'var(--radius-sm)',
        color,
      }}
    >
      <Icon name={iconName} size={Math.round(size * 0.52)} />
    </div>
  );
}
