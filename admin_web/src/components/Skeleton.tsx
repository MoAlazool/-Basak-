import React from 'react';

/** A grey placeholder the size of what is coming. Used only for a true first load. */
export const Skeleton: React.FC<{ className?: string }> = ({ className = '' }) => (
  <div className={`animate-pulse rounded-lg bg-slate-200/60 ${className}`} />
);

/** Rows of a list or table that has never been loaded in this session. */
export const SkeletonRows: React.FC<{ rows?: number; className?: string }> = ({ rows = 4, className = '' }) => (
  <div className={`space-y-3 p-5 ${className}`} aria-busy="true" aria-label="جاري التحميل">
    {Array.from({ length: rows }, (_, index) => (
      <div key={index} className="flex items-center gap-3">
        <Skeleton className="h-9 w-9 rounded-xl" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-3.5 w-2/5" />
          <Skeleton className="h-3 w-3/5" />
        </div>
        <Skeleton className="h-7 w-20" />
      </div>
    ))}
  </div>
);

/** A small note while fresh data is fetched behind what is already on screen. */
export const Refreshing: React.FC<{ active: boolean }> = ({ active }) => (
  active ? <span className="text-[11px] font-medium text-slate-400" role="status">جاري التحديث…</span> : null
);

const busy = { 'aria-busy': true, 'aria-label': 'جاري التحميل' } as const;

/** A grid of cards (lines, companies, supervisors, payment methods): a title, chips and a row of buttons each. */
export const SkeletonCards: React.FC<{ count?: number; columns?: 1 | 2 | 3 }> = ({ count = 3, columns = 1 }) => (
  <div {...busy} className={`grid gap-4 ${columns === 3 ? 'md:grid-cols-2 xl:grid-cols-3' : columns === 2 ? 'md:grid-cols-2' : ''}`}>
    {Array.from({ length: count }, (_, index) => (
      <div key={index} className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1 space-y-3">
            <div className="flex items-center gap-2">
              <Skeleton className="h-5 w-40" />
              <Skeleton className="h-5 w-14 rounded-full" />
            </div>
            <div className="flex flex-wrap gap-2">
              <Skeleton className="h-6 w-20" /><Skeleton className="h-6 w-24" /><Skeleton className="h-6 w-16" />
            </div>
            <Skeleton className="h-3.5 w-3/5" />
          </div>
          <div className="hidden gap-2 sm:flex">
            <Skeleton className="h-8 w-20" /><Skeleton className="h-8 w-16" />
          </div>
        </div>
      </div>
    ))}
  </div>
);

/** A table that has never been loaded: its header and rows, column for column. */
export const SkeletonTable: React.FC<{ rows?: number; columns?: number }> = ({ rows = 6, columns = 5 }) => (
  <div {...busy} className="overflow-hidden">
    <div className="flex gap-4 border-b border-slate-100 bg-slate-50/60 px-5 py-3.5">
      {Array.from({ length: columns }, (_, c) => <Skeleton key={c} className="h-3 flex-1" />)}
    </div>
    {Array.from({ length: rows }, (_, r) => (
      <div key={r} className="flex items-center gap-4 border-b border-slate-50 px-5 py-4">
        {Array.from({ length: columns }, (_, c) => (
          <div key={c} className="flex-1 space-y-1.5">
            <Skeleton className={`h-3.5 ${c === 0 ? 'w-4/5' : 'w-3/5'}`} />
            {c === 0 && <Skeleton className="h-3 w-2/5" />}
          </div>
        ))}
      </div>
    ))}
  </div>
);

/** A settings card: a heading, a line of help and a few labelled fields with a switch. */
export const SkeletonForm: React.FC<{ fields?: number }> = ({ fields = 3 }) => (
  <div {...busy} className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
    <Skeleton className="h-5 w-48" />
    <Skeleton className="mt-2 h-3 w-3/5" />
    <div className="mt-5 space-y-4">
      {Array.from({ length: fields }, (_, index) => (
        <div key={index} className="flex items-center justify-between gap-4">
          <div className="flex-1 space-y-2"><Skeleton className="h-3.5 w-1/3" /><Skeleton className="h-9 w-full" /></div>
          <Skeleton className="h-7 w-16 rounded-full" />
        </div>
      ))}
    </div>
  </div>
);

/** The whole workspace before its company is known: the sidebar, the four numbers and a panel. */
export const SkeletonShell: React.FC = () => (
  <div {...busy} className="flex min-h-screen" dir="rtl">
    <aside className="hidden w-[230px] flex-shrink-0 space-y-3 border-l border-slate-100 bg-white/70 p-4 md:block">
      <div className="mb-6 flex items-center gap-3"><Skeleton className="h-10 w-10 rounded-xl" /><Skeleton className="h-4 w-24" /></div>
      {Array.from({ length: 9 }, (_, index) => <Skeleton key={index} className="h-9 w-full rounded-2xl" />)}
    </aside>
    <main className="flex-1 space-y-6 p-4 sm:p-6">
      <Skeleton className="h-8 w-64" />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }, (_, index) => <Skeleton key={index} className="h-28 rounded-3xl" />)}
      </div>
      <div className="grid gap-6 lg:grid-cols-12">
        <Skeleton className="h-72 rounded-3xl lg:col-span-7" />
        <Skeleton className="h-72 rounded-3xl lg:col-span-5" />
      </div>
    </main>
  </div>
);
