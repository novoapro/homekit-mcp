import { useRef, useEffect } from 'react';
import { useLocation } from 'react-router';
import './PageTransition.css';

interface PageTransitionProps {
  children: React.ReactNode;
}

export function PageTransition({ children }: PageTransitionProps) {
  const location = useLocation();
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    // Re-trigger animation on route change
    el.classList.remove('page-enter');
    // Force reflow
    void el.offsetWidth;
    el.classList.add('page-enter');
  }, [location.pathname]);

  return (
    <div ref={containerRef} className="page-transition page-enter">
      {children}
    </div>
  );
}
