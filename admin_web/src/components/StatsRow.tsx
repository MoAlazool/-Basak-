import React from 'react';
import type { LucideIcon } from 'lucide-react';

export interface StatCard {
  label: string;
  value: string;
  hint: string;
  icon: LucideIcon;
  tone: 'blue' | 'green' | 'amber' | 'rose';
}

const tones: Record<StatCard['tone'], string> = {
  blue: 'bg-[#D6EEF9] text-[#3E8FBF]',
  green: 'bg-[#DDF3E6] text-[#2E9E5B]',
  amber: 'bg-[#FFF1D6] text-[#B8860B]',
  rose: 'bg-rose-100 text-rose-600',
};

export const egp = (amount: number) => `${amount.toLocaleString('ar-EG')} ج.م`;
export const count = (value: number) => value.toLocaleString('ar-EG');

export const StatsRow: React.FC<{ cards: StatCard[]; loading: boolean }> = ({ cards, loading }) => (
  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
    {cards.map((card, idx) => {
      const Icon = card.icon;
      return (
        <div
          key={card.label}
          className="glass-panel p-5 transition-all duration-300 hover:-translate-y-1 hover:shadow-lg hover:shadow-[#7EC8E3]/30"
          style={{ animation: `fadeIn 0.5s ease-out ${idx * 0.04}s both` }}
        >
          <div className="flex items-center justify-between">
            <span className="text-[12.5px] font-semibold text-[#5B6B7A]">{card.label}</span>
            <div className={`h-9 w-9 rounded-xl ${tones[card.tone]} flex items-center justify-center`}>
              <Icon className="h-4 w-4" />
            </div>
          </div>
          <div className="mt-3">
            {loading
              ? <div className="h-8 w-24 bg-slate-200/50 animate-pulse rounded-lg" />
              : <div className="text-[28px] font-extrabold text-[#1F2937] tracking-tight leading-none">{card.value}</div>}
          </div>
          <div className="mt-3 pt-2.5 border-t border-slate-100 text-[11.5px] font-medium text-[#5B6B7A]">{card.hint}</div>
        </div>
      );
    })}
  </div>
);
