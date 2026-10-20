import React, { useLayoutEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Icon, type IconName } from './Icon';
import { TONE, type Tone } from './Status';
import { IconButton } from './Button';

const FOCUSABLE = 'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';
const stack: HTMLElement[] = [];

/**
 * Escape closes the topmost layer, Tab stays inside it, focus moves in on open
 * and back to what opened it on close. Scrolling the page behind is stopped.
 */
function useLayer(open: boolean, onClose: () => void) {
  const ref = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useLayoutEffect(() => {
    if (!open || !ref.current) return undefined;
    const el = ref.current;
    const before = document.activeElement as HTMLElement | null;
    stack.push(el);
    const first = el.querySelector<HTMLElement>('[data-autofocus]') ?? el.querySelector<HTMLElement>(FOCUSABLE);
    (first ?? el).focus({ preventScroll: true });
    const body = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (stack[stack.length - 1] !== el) return;
      if (e.key === 'Escape') { e.stopPropagation(); close.current(); return; }
      if (e.key !== 'Tab') return;
      const items = [...el.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((x) => x.offsetParent !== null);
      if (!items.length) { e.preventDefault(); return; }
      const a = items[0]; const z = items[items.length - 1];
      if (e.shiftKey && document.activeElement === a) { e.preventDefault(); z.focus(); }
      else if (!e.shiftKey && document.activeElement === z) { e.preventDefault(); a.focus(); }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      stack.splice(stack.indexOf(el), 1);
      if (!stack.length) document.body.style.overflow = body;
      before?.focus?.({ preventScroll: true });
    };
  }, [open]);
  return ref;
}

const Scrim: React.FC<{ where: 'center' | 'end' | 'start' | 'sheet'; onClose: () => void; children: React.ReactNode }> = ({ where, onClose, children }) => {
  const lay = { center: 'items-end justify-center sm:items-center', end: 'items-stretch justify-end', start: 'items-stretch justify-start', sheet: 'items-end justify-center sm:items-stretch sm:justify-end' }[where];
  return createPortal(
    <div className={`scrim-enter fixed inset-x-0 bottom-0 top-[var(--ws-top,0px)] z-[60] flex bg-[rgba(23,56,74,.45)] ${lay}`} onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>{children}</div>,
    document.body,
  );
};

/**
 * A yes/no about one action. Desktop: centred, 480. Phone: anchored to the bottom, buttons stacked, the confirming one first.
 * Title is the question; the body says exactly what will and will not happen; the confirm button repeats the verb; cancel is «رجوع».
 */
export const Dialog: React.FC<{
  open: boolean; onClose: () => void; title: React.ReactNode; children?: React.ReactNode;
  /** [cancel, confirm] — rendered in that order on desktop, reversed on a phone. */
  actions?: React.ReactNode[]; icon?: IconName; tone?: Tone; w?: number;
}> = ({ open, onClose, title, children, actions = [], icon, tone = 'teal', w = 480 }) => {
  const ref = useLayer(open, onClose);
  if (!open) return null;
  return (
    <Scrim where="center" onClose={onClose}>
      <div ref={ref} tabIndex={-1} role="alertdialog" aria-modal="true" aria-labelledby="dlg-title"
        className="enter flex max-h-[92vh] w-full flex-col gap-4 overflow-y-auto rounded-t-dialog bg-surface px-4 pb-4 pt-5 shadow-floating outline-none sm:w-[var(--w)] sm:max-w-[calc(100vw-48px)] sm:gap-6 sm:rounded-dialog sm:p-6"
        style={{ '--w': `${w}px` } as React.CSSProperties}>
        <div className="flex flex-col gap-3 sm:flex-row sm:gap-4">
          {icon && <span aria-hidden="true" className={`flex h-11 w-11 flex-none items-center justify-center rounded-full ${TONE[tone]}`}><Icon name={icon} size={22} /></span>}
          <div className="flex min-w-0 flex-1 flex-col gap-1.5">
            <h2 id="dlg-title" className="m-0 text-section">{title}</h2>
            {children && <div className="flex flex-col gap-3 text-small text-ink-2">{children}</div>}
          </div>
        </div>
        {actions.length > 0 && <div className="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end [&>*]:w-full sm:[&>*]:w-auto">{actions}</div>}
      </div>
    </Scrim>
  );
};

/**
 * One record, read or edited: 480 wide at the end side on desktop and tablet; a full page with a back arrow on a phone.
 * `footer`: the main action at the end, a destructive one at the start.
 */
export const SidePanel: React.FC<{
  open: boolean; onClose: () => void; title: React.ReactNode; sub?: React.ReactNode; meta?: React.ReactNode;
  children: React.ReactNode; footer?: React.ReactNode; w?: number; backLabel?: string;
}> = ({ open, onClose, title, sub, meta, children, footer, w = 480, backLabel = 'رجوع' }) => {
  const ref = useLayer(open, onClose);
  if (!open) return null;
  return (
    <Scrim where="end" onClose={onClose}>
      <aside ref={ref} tabIndex={-1} role="dialog" aria-modal="true" aria-labelledby="panel-title"
        className="panel-enter flex h-full w-full flex-col bg-ground shadow-floating outline-none sm:w-[var(--w)] sm:max-w-[100vw] sm:bg-surface"
        style={{ '--w': `${w}px` } as React.CSSProperties}>
        {/* Phone: the top bar of a record's page. */}
        <div className="flex h-14 flex-none items-center gap-1 border-b border-hair bg-surface px-1 sm:hidden">
          <button type="button" onClick={onClose} aria-label={`رجوع إلى ${backLabel}`} className="flex h-12 w-12 items-center justify-center rounded-control text-ink"><Icon name="arrowBack" size={20} /></button>
          <span className="min-w-0 flex-1 truncate text-[17px] font-semibold leading-[26px]">{typeof title === 'string' ? title : backLabel}</span>
        </div>
        {/* On a phone the title is already in the bar above; only its status and second line stay here. */}
        <header className={`${sub || meta ? 'flex' : 'hidden sm:flex'} flex-none items-start gap-3 border-b border-hair bg-surface px-4 pb-3 pt-3 sm:px-6 sm:pb-4 sm:pt-5`}>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2.5"><h2 id="panel-title" className="m-0 text-section max-sm:sr-only">{title}</h2>{meta}</div>
            {sub && <div className="text-label text-ink-2">{sub}</div>}
          </div>
          <IconButton icon="x" label="إغلاق" onClick={onClose} className="-me-2 -mt-1.5 hidden sm:inline-flex" />
        </header>
        <div className="flex min-h-0 flex-1 flex-col gap-5 overflow-y-auto px-4 py-5 sm:px-6">{children}</div>
        {footer && <footer className="flex flex-none flex-col-reverse gap-2 border-t border-hair bg-surface px-4 py-3 sm:flex-row sm:items-center sm:px-6 sm:py-4">{footer}</footer>}
      </aside>
    </Scrim>
  );
};

/** A wide editor (a whole line, a whole company) over the page: full screen on a phone, a large centred sheet above. */
export const Sheet: React.FC<{ open: boolean; onClose: () => void; title: React.ReactNode; children: React.ReactNode; footer?: React.ReactNode; w?: number }> = ({ open, onClose, title, children, footer, w = 880 }) => {
  const ref = useLayer(open, onClose);
  if (!open) return null;
  return (
    <Scrim where="center" onClose={onClose}>
      <div ref={ref} tabIndex={-1} role="dialog" aria-modal="true" aria-labelledby="sheet-title"
        className="enter flex h-full w-full flex-col bg-ground shadow-floating outline-none sm:h-auto sm:max-h-[92vh] sm:w-[var(--w)] sm:max-w-[calc(100vw-48px)] sm:rounded-dialog"
        style={{ '--w': `${w}px` } as React.CSSProperties}>
        <header className="flex h-14 flex-none items-center gap-2 border-b border-hair bg-surface px-1 sm:h-16 sm:rounded-t-dialog sm:px-6">
          <IconButton icon="x" label="إغلاق" onClick={onClose} tone="ink" className="sm:hidden" />
          <h2 id="sheet-title" className="m-0 min-w-0 flex-1 truncate text-[17px] font-semibold sm:text-section">{title}</h2>
          <IconButton icon="x" label="إغلاق" onClick={onClose} className="-me-2 hidden sm:inline-flex" />
        </header>
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4 sm:gap-5 sm:p-6">{children}</div>
        {footer && <footer className="flex flex-none flex-col-reverse gap-2 border-t border-hair bg-surface px-4 py-3 sm:flex-row sm:items-center sm:rounded-b-dialog sm:px-6 sm:py-4">{footer}</footer>}
      </div>
    </Scrim>
  );
};

/** The drawer the phone menu button opens (start side, full height). */
export const Drawer: React.FC<{ open: boolean; onClose: () => void; label: string; children: React.ReactNode; className?: string }> = ({ open, onClose, label, children, className = '' }) => {
  const ref = useLayer(open, onClose);
  if (!open) return null;
  return (
    <Scrim where="start" onClose={onClose}>
      <nav ref={ref} tabIndex={-1} aria-label={label} className={`drawer-enter flex h-full w-[320px] max-w-[88vw] flex-col bg-surface shadow-floating outline-none ${className}`}>{children}</nav>
    </Scrim>
  );
};
