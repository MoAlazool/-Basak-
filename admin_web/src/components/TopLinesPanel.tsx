import React from 'react';
import { Award, ChevronLeft } from 'lucide-react';

interface TopLineItem {
  id: string;
  name: string;
  companyName: string;
  subscriberCount: number;
  isActive: boolean;
}

interface TopLinesProps {
  lines: TopLineItem[];
  loading: boolean;
}

export const TopLinesPanel: React.FC<TopLinesProps> = ({ lines, loading }) => {
  return (
    <div className="glass-panel p-6 flex flex-col justify-between h-full">
      <div>
        <div className="flex items-center justify-between pb-4 border-b border-slate-100">
          <div className="flex items-center gap-2.5">
            <div className="h-8 w-8 rounded-lg bg-[#DDF3E6] flex items-center justify-center text-[#2E9E5B]">
              <Award className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-[16px] font-bold text-[#1F2937]">الخطوط الأكثر اشتراكاً</h2>
              <p className="text-[12px] font-medium text-[#5B6B7A]">ترتيب خطوط السير حسب إجمالي الطلاب النشطين</p>
            </div>
          </div>
        </div>

        {/* List of lines */}
        <div className="mt-5 space-y-3">
          {loading ? (
            <div className="py-12 text-center text-sm text-[#5B6B7A]">جاري تحميل الخطوط...</div>
          ) : lines.length === 0 ? (
            <div className="py-12 text-center text-sm text-[#5B6B7A]">لا توجد اشتراكات نشطة بعد.</div>
          ) : (
            lines.slice(0, 5).map((line, idx) => (
              <div
                key={line.id}
                className="flex items-center justify-between p-3 rounded-2xl bg-white/50 border border-white/60 hover:bg-white/80 transition-all duration-200"
              >
                <div className="flex items-center gap-3">
                  <div className="h-7 w-7 rounded-lg bg-[#D6EEF9] text-[#3E8FBF] font-extrabold text-xs flex items-center justify-center">
                    {idx + 1}
                  </div>
                  <div>
                    <h3 className="text-[13.5px] font-bold text-[#1F2937] leading-snug">{line.name}</h3>
                    <p className="text-[11.5px] text-[#5B6B7A]">{line.companyName}</p>
                  </div>
                </div>

                <div className="flex items-center gap-3">
                  <div className="text-right">
                    <span className="text-[13.5px] font-extrabold text-[#1F2937]">{line.subscriberCount}</span>
                    <span className="text-[11px] text-[#5B6B7A] mr-1">طالب</span>
                  </div>
                  <span className={line.isActive ? 'pill-active' : 'pill-rejected'}>
                    {line.isActive ? 'نشط' : 'متوقف'}
                  </span>
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-[11.5px] text-[#3E8FBF] font-bold cursor-pointer hover:underline">
        <span>عرض كافة خطوط السير وتفاصيلها</span>
        <ChevronLeft className="h-4 w-4" />
      </div>
    </div>
  );
};
