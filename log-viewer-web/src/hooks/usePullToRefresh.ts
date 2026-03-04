import { useCallback, useRef } from 'react';

const THRESHOLD = 60;

interface UsePullToRefreshOptions {
  onRefresh: () => Promise<void>;
  disabled?: boolean;
}

export function usePullToRefresh({ onRefresh, disabled }: UsePullToRefreshOptions) {
  const startYRef = useRef(0);
  const pullingRef = useRef(false);
  const refreshingRef = useRef(false);

  const bindToElement = useCallback(
    (el: HTMLElement | null) => {
      if (!el) return;

      // Prevent native pull-to-refresh
      el.style.overscrollBehaviorY = 'contain';

      const onTouchStart = (e: TouchEvent) => {
        if (disabled || refreshingRef.current) return;
        if (el.scrollTop <= 0) {
          startYRef.current = e.touches[0]!.clientY;
          pullingRef.current = true;
        }
      };

      const onTouchMove = () => {
        // No-op: just need the listener for completeness
      };

      const onTouchEnd = (e: TouchEvent) => {
        if (!pullingRef.current) return;
        pullingRef.current = false;

        const endY = e.changedTouches[0]!.clientY;
        const distance = endY - startYRef.current;

        if (distance >= THRESHOLD && el.scrollTop <= 0) {
          refreshingRef.current = true;
          onRefresh().finally(() => {
            refreshingRef.current = false;
          });
        }
      };

      el.addEventListener('touchstart', onTouchStart, { passive: true });
      el.addEventListener('touchmove', onTouchMove, { passive: true });
      el.addEventListener('touchend', onTouchEnd, { passive: true });

      // Store cleanup for when ref changes
      (el as any).__pullToRefreshCleanup?.();
      (el as any).__pullToRefreshCleanup = () => {
        el.removeEventListener('touchstart', onTouchStart);
        el.removeEventListener('touchmove', onTouchMove);
        el.removeEventListener('touchend', onTouchEnd);
      };
    },
    [onRefresh, disabled],
  );

  return { bindToElement };
}
