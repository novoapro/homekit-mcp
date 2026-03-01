import { useRef, useEffect, useCallback } from 'react';
import { Icon } from './Icon';
import './ConfirmDialog.css';

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  const confirmBtnRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (open) {
      // Focus the cancel button (safer default) after animation
      const timer = setTimeout(() => confirmBtnRef.current?.focus(), 100);
      return () => clearTimeout(timer);
    }
  }, [open]);

  // Close on Escape
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'Escape') onCancel();
    },
    [onCancel],
  );

  if (!open) return null;

  return (
    <div className="cd-overlay" onClick={onCancel} onKeyDown={handleKeyDown} role="dialog" aria-modal="true" aria-labelledby="cd-title">
      <div className="cd-dialog" onClick={(e) => e.stopPropagation()}>
        <div className={`cd-icon-wrap${destructive ? ' destructive' : ''}`}>
          <Icon name={destructive ? 'exclamation-triangle' : 'questionmark-circle'} size={24} />
        </div>
        <h3 id="cd-title" className="cd-title">{title}</h3>
        <p className="cd-message">{message}</p>
        <div className="cd-actions">
          <button type="button" className="cd-btn cancel" onClick={onCancel}>
            {cancelLabel}
          </button>
          <button
            ref={confirmBtnRef}
            type="button"
            className={`cd-btn confirm${destructive ? ' destructive' : ''}`}
            onClick={onConfirm}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
