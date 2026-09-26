import React from 'react';
import { Users, Bus, Building2, Wallet } from 'lucide-react';

interface StatsProps {
  activeStudents: number;
  ridingToday: number;
  companiesCount: number;
  monthlyRevenue: number;
  loading: boolean;
}

export const StatsRow: React.FC<StatsProps> = ({
  activeStudents,
  ridingToday,
  companiesCount,
  monthlyRevenue,
  loading,
}) => {
  const cards = [
    {
      label: 'الطلاب المشتركون (النشطون)',
      value: activeStudents,
      displayValue: activeStudents.toLocaleString('ar-EG'),
      delta: '+12% عن الشهر الماضي',
      deltaColor: 'text-[#2E9E5B]',
      icon: Users,
      iconBg: 'bg-[#D6EEF9]',
      iconColor: 'text-[#3E8FBF]',
    },
    {
      label: 'نازلين اليوم (مؤكدين)',
      value: ridingToday,
      displayValue: ridingToday.toLocaleString('ar-EG'),
      delta: 'حسب مفتاح نازل بكرة',
      deltaColor: 'text-[#5B6B7A]',
      icon: Bus,
      iconBg: 'bg-[#DDF3E6]',
      iconColor: 'text-[#2E9E5B]',
    },
    {
      label: 'شركات النقل المعتمدة',
      value: companiesCount,
      displayValue: companiesCount.toLocaleString('ar-EG'),
      delta: 'تعمل بكامل خطوطها',
      deltaColor: 'text-[#5B6B7A]',
      icon: Building2,
      iconBg: 'bg-[#FFF1D6]',
      iconColor: 'text-[#B8860B]',
    },
    {
      label: 'الإيرادات الشهرية المقدرة',
      value: monthlyRevenue,
      displayValue: `${monthlyRevenue.toLocaleString('ar-EG')} ج.م`,
      delta: 'مسددة عبر تحويلات بنكية',
      deltaColor: 'text-[#2E9E5B]',
      icon: Wallet,
      iconBg: 'bg-[#EBF5FB]',
      iconColor: 'text-[#3E8FBF]',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      {cards.map((c, idx) => {
        const Icon = c.icon;
        return (
          <div
            key={idx}
            className="glass-panel p-5 transition-all duration-300 hover:-translate-y-1 hover:shadow-lg hover:shadow-[#7EC8E3]/30"
            style={{
              animation: `fadeIn 0.5s ease-out ${idx * 0.04}s both`,
            }}
          >
            <div className="flex items-center justify-between">
              <span className="text-[12.5px] font-semibold text-[#5B6B7A]">{c.label}</span>
              <div className={`h-9 w-9 rounded-xl ${c.iconBg} ${c.iconColor} flex items-center justify-center`}>
                <Icon className="h-4 w-4" />
              </div>
            </div>

            <div className="mt-3">
              {loading ? (
                <div className="h-8 w-24 bg-slate-200/50 animate-pulse rounded-lg" />
              ) : (
                <div className="text-[28px] font-extrabold text-[#1F2937] tracking-tight leading-none">
                  {c.displayValue}
                </div>
              )}
            </div>

            <div className="mt-3 pt-2.5 border-t border-slate-100 flex items-center gap-1.5 text-[11.5px] font-medium">
              <span className={c.deltaColor}>{c.delta}</span>
            </div>
          </div>
        );
      })}
    </div>
  );
};
