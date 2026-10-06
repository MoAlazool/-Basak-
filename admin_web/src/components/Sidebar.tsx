import React from 'react';
import { NavLink } from 'react-router-dom';
import { LogOut, ShieldCheck } from 'lucide-react';
import { BasakLogo } from './BasakLogo';
import type { NavItem } from '../lib/nav';

interface NavProps {
  items: NavItem[];
  /** Shown under the brand: which area or company these pages belong to. */
  areaLabel: string;
  onLogout: () => void;
}

export const Sidebar: React.FC<NavProps> = ({ items, areaLabel, onLogout }) => (
  <aside
    className="sticky top-0 h-screen w-[72px] lg:w-[230px] flex flex-col justify-between py-5 px-3 z-30 flex-shrink-0 overflow-y-auto"
    style={{
      background: 'rgba(255,255,255,0.72)',
      backdropFilter: 'blur(18px)',
      WebkitBackdropFilter: 'blur(18px)',
      borderLeft: '1px solid rgba(255,255,255,0.7)',
      boxShadow: '4px 0 24px rgba(126,200,227,0.12)',
    }}
  >
    <div>
      <div className="flex items-center gap-3 px-2 py-3 mb-4 border-b border-white/40">
        <BasakLogo className="h-10 w-10 min-w-[40px]" />
        <div className="hidden lg:block min-w-0">
          <h1 className="text-base font-extrabold text-[#1F2937] leading-tight">باصك</h1>
          <p className="truncate text-[11px] font-medium text-[#5B6B7A]" title={areaLabel}>{areaLabel}</p>
        </div>
      </div>

      <nav className="space-y-1">
        {items.map(({ to, name, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            title={name}
            className={({ isActive }) => `flex w-full items-center gap-3 px-3 py-2.5 rounded-2xl text-[13px] font-semibold transition-all duration-150 ${
              isActive ? 'bg-[#D6EEF9]/80 text-[#3E8FBF] shadow-sm' : 'text-[#5B6B7A] hover:bg-white/60 hover:text-[#1F2937]'
            }`}
          >
            <Icon className="h-5 w-5 min-w-[20px]" />
            <span className="hidden lg:inline">{name}</span>
          </NavLink>
        ))}
      </nav>
    </div>

    <div className="space-y-2 pt-4">
      <div className="hidden lg:flex items-center gap-2 p-3 rounded-2xl bg-white/50 border border-white/60 text-[11px] text-[#5B6B7A]">
        <ShieldCheck className="h-4 w-4 text-[#3E8FBF] flex-shrink-0" />
        <span>نظام محمي ومشفر بالكامل</span>
      </div>
      <button
        onClick={onLogout}
        title="تسجيل الخروج"
        className="flex w-full items-center gap-3 px-3 py-2.5 rounded-2xl text-[13px] font-semibold text-rose-500 hover:bg-rose-50 transition"
      >
        <LogOut className="h-5 w-5 min-w-[20px]" />
        <span className="hidden lg:inline">تسجيل الخروج</span>
      </button>
    </div>
  </aside>
);

/** The same pages as the sidebar, as a bottom bar on phones. */
export const MobileNav: React.FC<NavProps> = ({ items, onLogout }) => (
  <nav
    className="md:hidden fixed bottom-0 left-0 right-0 z-40 flex items-center justify-between overflow-x-auto px-2 py-2"
    style={{
      background: 'rgba(255,255,255,0.92)',
      backdropFilter: 'blur(20px)',
      WebkitBackdropFilter: 'blur(20px)',
      borderTop: '1px solid rgba(255,255,255,0.7)',
      boxShadow: '0 -4px 24px rgba(126,200,227,0.15)',
    }}
  >
    {items.map(({ to, short, icon: Icon, end }) => (
      <NavLink key={to} to={to} end={end} className="flex flex-col items-center gap-0.5 px-2 py-1 rounded-xl transition-all flex-shrink-0">
        {({ isActive }) => (
          <>
            <Icon className={`h-5 w-5 transition-colors ${isActive ? 'text-[#3E8FBF]' : 'text-slate-400'}`} />
            <span className={`text-[9.5px] font-bold transition-colors ${isActive ? 'text-[#3E8FBF]' : 'text-slate-400'}`}>{short}</span>
            {isActive && <div className="h-1 w-4 rounded-full bg-[#7EC8E3] mt-0.5" />}
          </>
        )}
      </NavLink>
    ))}
    <button onClick={onLogout} className="flex flex-col items-center gap-0.5 px-2 py-1 rounded-xl flex-shrink-0">
      <LogOut className="h-5 w-5 text-rose-400" />
      <span className="text-[9.5px] font-bold text-rose-400">خروج</span>
    </button>
  </nav>
);
