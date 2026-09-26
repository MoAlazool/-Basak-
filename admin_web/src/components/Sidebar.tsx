import React from 'react';
import {
  LayoutDashboard,
  Building2,
  Bus,
  UserCheck,
  FileCheck2,
  BarChart3,
  ShieldCheck,
} from 'lucide-react';

interface SidebarProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange }) => {
  const navItems = [
    { id: 'overview', name: 'نظرة عامة', icon: LayoutDashboard },
    { id: 'companies', name: 'الشركات', icon: Building2 },
    { id: 'lines', name: 'الخطوط والمحطات', icon: Bus },
    { id: 'supervisors', name: 'المشرفون', icon: UserCheck },
    { id: 'receipts', name: 'فحص الإيصالات', icon: FileCheck2 },
    { id: 'reports', name: 'التقارير المالية', icon: BarChart3 },
  ];

  return (
    <aside className="sticky top-6 h-[calc(100vh-3rem)] w-20 lg:w-[230px] transition-all duration-300 flex flex-col justify-between p-4 glass-panel z-30">
      <div>
        {/* Brand Mark */}
        <div className="flex items-center gap-3 px-2 py-3 mb-6 border-b border-white/40">
          <div className="h-10 w-10 min-w-[40px] rounded-xl bg-gradient-to-tr from-[#3E8FBF] to-[#7EC8E3] flex items-center justify-center text-white shadow-md shadow-[#7EC8E3]/30">
            <Bus className="h-5 w-5" />
          </div>
          <div className="hidden lg:block">
            <h1 className="text-base font-extrabold text-[#1F2937] leading-tight">باصك</h1>
            <p className="text-[11px] font-medium text-[#5B6B7A]">لوحة تحكم الإدارة</p>
          </div>
        </div>

        {/* Navigation Items */}
        <nav className="space-y-1.5">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeTab === item.id;
            return (
              <button
                key={item.id}
                onClick={() => onTabChange(item.id)}
                className={`flex w-full items-center gap-3.5 px-3.5 py-3 rounded-2xl text-[13.5px] font-semibold transition-all duration-200 ${
                  isActive
                    ? 'bg-[#D6EEF9]/80 text-[#3E8FBF] shadow-sm shadow-[#7EC8E3]/20'
                    : 'text-[#5B6B7A] hover:bg-white/60 hover:text-[#1F2937]'
                }`}
                title={item.name}
              >
                <Icon className={`h-5 w-5 min-w-[20px] ${isActive ? 'text-[#3E8FBF]' : 'text-[#5B6B7A]'}`} />
                <span className="hidden lg:inline">{item.name}</span>
              </button>
            );
          })}
        </nav>
      </div>

      {/* Admin Security Badge */}
      <div className="hidden lg:flex items-center gap-2 p-3 rounded-2xl bg-white/50 border border-white/60 text-[11.5px] text-[#5B6B7A]">
        <ShieldCheck className="h-4 w-4 text-[#3E8FBF]" />
        <span>نظام محمي ومشفر بالكامل</span>
      </div>
    </aside>
  );
};
