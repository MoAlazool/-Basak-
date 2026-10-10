import React from 'react';
import { BasakLogo } from './BasakLogo';
import { MobileNav, Sidebar } from './Sidebar';
import type { NavItem } from '../lib/nav';
import { Toasts } from './Toasts';

interface ShellProps {
  items: NavItem[];
  areaLabel: string;
  /** A company's mark, shown in place of the product's in that company's workspace. */
  mark?: React.ReactNode;
  onLogout: () => void;
  /** Sits above every page of the area (the workspace's company bar). */
  banner?: React.ReactNode;
  /** Counts shown as red badges on the navigation. */
  badges?: Partial<Record<NonNullable<NavItem['badge']>, number>>;
  children: React.ReactNode;
}

/** The frame shared by the platform area and every company workspace. */
export const Shell: React.FC<ShellProps> = ({ items, areaLabel, mark, onLogout, banner, badges, children }) => (
  <div className="flex min-h-screen" dir="rtl">
    <div className="hidden md:flex">
      <Sidebar items={items} areaLabel={areaLabel} mark={mark} onLogout={onLogout} badges={badges} />
    </div>
    <main
      className="flex-1 min-w-0 overflow-x-hidden pb-24 md:pb-8"
      style={{
        background: 'radial-gradient(ellipse 80% 60% at 20% 10%, #EAF7FD 0%, #F3FAFD 50%, #ffffff 100%)',
        minHeight: '100vh',
      }}
    >
      <div className="mx-auto max-w-[1400px] p-4 sm:p-6 space-y-0">
        <div className="md:hidden flex items-center gap-2.5 mb-4">
          {mark ?? <BasakLogo className="h-9 w-9" />}
          <div className="min-w-0">
            <p className="truncate text-base font-extrabold text-[#1F2937] leading-tight">{mark ? areaLabel : 'باصك'}</p>
            <p className="truncate text-[11px] font-medium text-[#5B6B7A]">{mark ? 'باصك' : areaLabel}</p>
          </div>
        </div>
        {banner}
        {children}
      </div>
    </main>
    <MobileNav items={items} areaLabel={areaLabel} onLogout={onLogout} badges={badges} />
    <Toasts />
  </div>
);
