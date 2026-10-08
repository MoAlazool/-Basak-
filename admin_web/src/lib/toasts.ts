import { useSyncExternalStore } from 'react';

/** A short notice shown on top of the dashboard when something new arrives. */
export interface Toast { id: number; title: string; body?: string; /** Page to open when it is clicked. */ to?: string }

let toasts: Toast[] = [];
let nextId = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((listener) => listener());

/** Shows a notice for a few seconds. The same title is not stacked twice. */
export function notify(toast: Omit<Toast, 'id'>, lifetimeMs = 9000) {
  if (toasts.some((t) => t.title === toast.title && t.to === toast.to)) return;
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
