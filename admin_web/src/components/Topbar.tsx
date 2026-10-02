import React from 'react';
import { User, Bell, Calendar } from 'lucide-react';
import { useAdminScope } from '../lib/adminScope';

interface TopbarProps {
  title: string;
  subtitle: string;
}

export const Topbar: React.FC<TopbarProps> = ({ title, subtitle }) => {
  const admin = useAdminScope();
  const todayDate = new Date().toLocaleDateString('ar-EG', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
  });

  return (
    <header className="flex flex-wrap items-center justify-between gap-4 mb-6">
      {/* Title & Date Subtitle */}
      <div>
        <h1 className="text-2xl font-extrabold text-[#1F2937] tracking-tight">{title}</h1>
        <div className="flex items-center gap-2 mt-1 text-[#5B6B7A] text-[12.5px] font-medium">
          <Calendar className="h-3.5 w-3.5 text-[#3E8FBF]" />
          <span>{todayDate}</span>
          <span className="text-slate-300">•</span>
          <span>{subtitle}</span>
        </div>
      </div>

      {/* Right: Notification & Admin Identity Chip */}
      <div className="flex items-center gap-3">
        <button className="h-10 w-10 rounded-full glass-pill flex items-center justify-center text-[#5B6B7A] hover:text-[#1F2937] transition">
          <Bell className="h-4 w-4" />
        </button>

        <div className="flex items-center gap-2.5 px-3 py-1.5 glass-pill">
          <div className="h-8 w-8 rounded-full bg-gradient-to-tr from-[#7EC8E3] to-[#3E8FBF] flex items-center justify-center text-white font-bold text-xs shadow-inner">
            <User className="h-4 w-4" />
          </div>
          <div className="text-right">
            <p className="text-[13px] font-bold text-[#1F2937] leading-none">{admin.companyName || admin.full_name || 'مدير النظام'}</p>
            <p className="text-[11px] font-medium text-[#3E8FBF] mt-0.5">{admin.role === 'super_admin' ? 'Super Admin' : 'مدير الشركة'}</p>
          </div>
        </div>
      </div>
    </header>
  );
};
