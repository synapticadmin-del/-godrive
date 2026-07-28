import { useEffect, useRef } from 'react';

/**
 * Visibility-aware polling.
 *
 * Runs `callback` immediately, then on a `intervalMs` cadence — but only while
 * the tab is visible. When the page is hidden (`document.hidden`), the
 * interval is cleared so we stop hammering the API for a screen nobody is
 * looking at; when it becomes visible again we refetch immediately and resume.
 *
 * The latest callback is always invoked (stored in a ref), so callers can pass
 * an inline closure without re-subscribing the interval on every render.
 */
export function usePolling(callback: () => void, intervalMs: number) {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;

    const run = () => callbackRef.current();

    const start = () => {
      if (interval == null) interval = setInterval(run, intervalMs);
    };

    const stop = () => {
      if (interval != null) {
        clearInterval(interval);
        interval = null;
      }
    };

    const onVisibility = () => {
      if (document.hidden) {
        stop();
      } else {
        // Refetch immediately on return so the admin isn't staring at stale
        // data for up to a full interval, then resume the cadence.
        run();
        start();
      }
    };

    // Initial fetch + start (the page may already be hidden on load, in which
    // case we skip the interval until it becomes visible).
    run();
    if (!document.hidden) start();

    document.addEventListener('visibilitychange', onVisibility);
    return () => {
      stop();
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, [intervalMs]);
}
