import { useEffect, useState } from 'react';
import './RefreshBar.css';

interface RefreshBarProps {
  isRefreshing: boolean;
}

export function RefreshBar({ isRefreshing }: RefreshBarProps) {
  const [visible, setVisible] = useState(false);
  const [completing, setCompleting] = useState(false);

  useEffect(() => {
    if (isRefreshing) {
      setCompleting(false);
      setVisible(true);
    } else if (visible) {
      // Brief "completing" state before hiding
      setCompleting(true);
      const timer = setTimeout(() => {
        setVisible(false);
        setCompleting(false);
      }, 400);
      return () => clearTimeout(timer);
    }
  }, [isRefreshing, visible]);

  if (!visible) return null;

  return (
    <div className={`refresh-bar ${completing ? 'completing' : 'active'}`}>
      <div className="refresh-bar-inner" />
    </div>
  );
}
