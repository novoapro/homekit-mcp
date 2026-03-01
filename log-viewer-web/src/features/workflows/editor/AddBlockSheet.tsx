import { Icon } from '@/components/Icon';
import { BLOCK_ICONS } from './block-helpers';
import './AddBlockSheet.css';

interface BlockOption {
  type: string;
  label: string;
  description: string;
}

const ACTION_BLOCKS: BlockOption[] = [
  { type: 'controlDevice', label: 'Control Device', description: 'Set a device characteristic value' },
  { type: 'runScene', label: 'Run Scene', description: 'Activate a HomeKit scene' },
  { type: 'webhook', label: 'Webhook', description: 'Send an HTTP request to a URL' },
  { type: 'log', label: 'Log', description: 'Write a message to the workflow log' },
];

const FLOW_BLOCKS: BlockOption[] = [
  { type: 'delay', label: 'Delay', description: 'Wait for a specified duration' },
  { type: 'waitForState', label: 'Wait for State', description: 'Pause until a condition is met' },
  { type: 'conditional', label: 'If / Else', description: 'Branch based on a condition' },
  { type: 'repeat', label: 'Repeat', description: 'Run blocks a fixed number of times' },
  { type: 'repeatWhile', label: 'Repeat While', description: 'Loop while a condition is true' },
  { type: 'group', label: 'Group', description: 'Organize blocks under a label' },
  { type: 'stop', label: 'Stop', description: 'End workflow with an outcome' },
  { type: 'executeWorkflow', label: 'Execute Workflow', description: 'Run another workflow' },
];

interface AddBlockSheetProps {
  open: boolean;
  onClose: () => void;
  onAdd: (type: string) => void;
}

export function AddBlockSheet({ open, onClose, onAdd }: AddBlockSheetProps) {
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
        <h3 className="abs-title">Add Block</h3>

        <div className="abs-group">
          <span className="abs-group-label">Actions</span>
          <div className="abs-options">
            {ACTION_BLOCKS.map((b) => (
              <button key={b.type} className="abs-option" onClick={() => handleAdd(b.type)} type="button">
                <span className="abs-option-icon action">
                  <Icon name={BLOCK_ICONS[b.type] || 'square'} size={16} />
                </span>
                <div className="abs-option-text">
                  <span className="abs-option-label">{b.label}</span>
                  <span className="abs-option-desc">{b.description}</span>
                </div>
              </button>
            ))}
          </div>
        </div>

        <div className="abs-group">
          <span className="abs-group-label">Flow Control</span>
          <div className="abs-options">
            {FLOW_BLOCKS.map((b) => (
              <button key={b.type} className="abs-option" onClick={() => handleAdd(b.type)} type="button">
                <span className="abs-option-icon flow">
                  <Icon name={BLOCK_ICONS[b.type] || 'square'} size={16} />
                </span>
                <div className="abs-option-text">
                  <span className="abs-option-label">{b.label}</span>
                  <span className="abs-option-desc">{b.description}</span>
                </div>
              </button>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
