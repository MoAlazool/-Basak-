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
