import { useState, useRef, useCallback, useEffect } from 'react';

interface UsePullToRefreshOptions {
  onRefresh: () => Promise<void>;
  threshold?: number;
  disabled?: boolean;
}

export function usePullToRefresh({
  onRefresh,
  threshold = 80,
  disabled = false,
}: UsePullToRefreshOptions) {
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  const startYRef = useRef(0);
  const pullingRef = useRef(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const handleTouchStart = useCallback(
    (e: TouchEvent) => {
      if (disabled || isRefreshing) return;
      const el = containerRef.current;
      if (!el || el.scrollTop > 0) return;
      startYRef.current = e.touches[0]!.clientY;
      pullingRef.current = true;
    },
    [disabled, isRefreshing],
  );

  const handleTouchMove = useCallback(
    (e: TouchEvent) => {
      if (!pullingRef.current || disabled || isRefreshing) return;
      const diff = e.touches[0]!.clientY - startYRef.current;
      if (diff > 0) {
        // Apply resistance
        setPullDistance(Math.min(diff * 0.4, threshold * 1.5));
      }
    },
    [disabled, isRefreshing, threshold],
  );

  const handleTouchEnd = useCallback(async () => {
    if (!pullingRef.current) return;
    pullingRef.current = false;

    if (pullDistance >= threshold && !isRefreshing) {
      setIsRefreshing(true);
      setPullDistance(threshold * 0.5); // Hold at indicator position
      try {
        await onRefresh();
      } finally {
        setIsRefreshing(false);
        setPullDistance(0);
      }
    } else {
      setPullDistance(0);
    }
  }, [pullDistance, threshold, isRefreshing, onRefresh]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    el.addEventListener('touchstart', handleTouchStart, { passive: true });
    el.addEventListener('touchmove', handleTouchMove, { passive: true });
    el.addEventListener('touchend', handleTouchEnd);

    return () => {
      el.removeEventListener('touchstart', handleTouchStart);
      el.removeEventListener('touchmove', handleTouchMove);
      el.removeEventListener('touchend', handleTouchEnd);
    };
  }, [handleTouchStart, handleTouchMove, handleTouchEnd]);

  return {
    containerRef,
    isRefreshing,
    pullDistance,
    pullStyle: pullDistance > 0 ? { transform: `translateY(${pullDistance}px)`, transition: pullingRef.current ? 'none' : 'transform 300ms ease-out' } : undefined,
  };
}
