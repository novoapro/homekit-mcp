import { Icon } from '@/components/Icon';
import './AddBlockSheet.css'; // reuse sheet styles

const TRIGGER_OPTIONS = [
  { type: 'deviceStateChange', label: 'Device State Change', description: 'Trigger when a device characteristic changes', icon: 'house' },
  { type: 'schedule', label: 'Schedule', description: 'Trigger on a time-based schedule', icon: 'clock' },
  { type: 'sunEvent', label: 'Sun Event', description: 'Trigger at sunrise or sunset', icon: 'sun-max' },
  { type: 'webhook', label: 'Webhook', description: 'Trigger via an external HTTP request', icon: 'globe' },
  { type: 'workflow', label: 'Callable', description: 'Can be invoked by other workflows', icon: 'arrow-triangle-branch' },
];

interface AddTriggerSheetProps {
  open: boolean;
  onClose: () => void;
  onAdd: (type: string) => void;
}

export function AddTriggerSheet({ open, onClose, onAdd }: AddTriggerSheetProps) {
  if (!open) return null;

  const handleAdd = (type: string) => {
    onAdd(type);
    onClose();
  };

  return (
    <>
      <div className="abs-overlay" onClick={onClose} />
      <div className="abs-sheet">
        <div className="abs-handle" />
        <h3 className="abs-title">Add Trigger</h3>

        <div className="abs-group">
          <div className="abs-options">
            {TRIGGER_OPTIONS.map((t) => (
              <button key={t.type} className="abs-option" onClick={() => handleAdd(t.type)} type="button">
                <span className="abs-option-icon action">
                  <Icon name={t.icon} size={16} />
                </span>
                <div className="abs-option-text">
                  <span className="abs-option-label">{t.label}</span>
                  <span className="abs-option-desc">{t.description}</span>
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
