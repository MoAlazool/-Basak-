import { useRef } from 'react';

/**
 * Runs one task per key at a time. A second call for a key whose task is still
 * running does nothing and answers `undefined`: a double click, a second Enter
 * or a click that lands before the button has been disabled cannot send the
 * same write twice. Different keys (two different rows) do not block each other.
 */
export function createGuard() {
  const running = new Set<string>();
  const run = async <T,>(key: string, task: () => Promise<T>): Promise<T | undefined> => {
    if (running.has(key)) return undefined;
    running.add(key);
    try {
      return await task();
    } finally {
      running.delete(key);
    }
  };
  return Object.assign(run, { isRunning: (key: string) => running.has(key) });
}

/** One guard for the life of a component. */
export function useGuard() {
  const guard = useRef<ReturnType<typeof createGuard>>();
  return (guard.current ??= createGuard());
}
