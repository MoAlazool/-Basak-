import { useSyncExternalStore } from 'react';

/** A short notice shown on top of the dashboard: something new arrived, or what the admin just did worked or failed. */
interface Toast { id: number; title: string; body?: string; /** Page to open when it is clicked. */ to?: string; /** `error` for something that failed, `success` for something done. */ tone?: 'info' | 'error' | 'success' }

let toasts: Toast[] = [];
let nextId = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((listener) => listener());

/** Shows a notice for a few seconds. The same title is not stacked twice. */
export function notify(toast: Omit<Toast, 'id'>, lifetimeMs = 9000) {
  if (toasts.some((t) => t.title === toast.title && t.to === toast.to && t.body === toast.body)) return;
  const id = nextId++;
  toasts = [...toasts, { ...toast, id }].slice(-4);
  emit();
  window.setTimeout(() => dismiss(id), lifetimeMs);
}

export function dismiss(id: number) {
  if (!toasts.some((t) => t.id === id)) return;
  toasts = toasts.filter((t) => t.id !== id);
  emit();
}

export function useToasts(): Toast[] {
  return useSyncExternalStore(
    (listener) => { listeners.add(listener); return () => { listeners.delete(listener); }; },
    () => toasts);
}

/** A failure, in the server's own words when it gave any. */
export const notifyError = (title: string, body?: string) => notify({ title, body, tone: 'error' }, lifetimeFor(body));

/** Something the admin asked for was done. A long explanation stays on screen longer. */
export const notifyDone = (title: string, body?: string) =>
  notify({ title, body, tone: 'success' }, lifetimeFor(body));

/** Nine seconds, and more for a text that takes longer to read (at most half a minute). */
export const lifetimeFor = (body?: string) => Math.min(30_000, Math.max(9000, (body?.length ?? 0) * 90));
