import React from 'react';
import { BarChart3 } from 'lucide-react';

interface DayRiderCount {
  dayName: string;
  dateStr: string;
  count: number;
}

interface WeeklyChartProps {
  data: DayRiderCount[];
  loading: boolean;
}

export const WeeklyRidersChart: React.FC<WeeklyChartProps> = ({ data, loading }) => {
  const maxCount = Math.max(...data.map((d) => d.count), 10);

  return (
    <div className="glass-panel p-6 flex flex-col justify-between h-full">
      <div>
        <div className="flex items-center justify-between pb-4 border-b border-slate-100">
          <div className="flex items-center gap-2.5">
            <div className="h-8 w-8 rounded-lg bg-[#D6EEF9] flex items-center justify-center text-[#3E8FBF]">
              <BarChart3 className="h-4 w-4" />
            </div>
            <div>
              <h2 className="text-[16px] font-bold text-[#1F2937]">نشاط الركاب خلال الأسبوع</h2>
              <p className="text-[12px] font-medium text-[#5B6B7A]">إحصاء الحضور اليومي الفعلي (مفتاح نازل بكرة)</p>
            </div>
          </div>
          <span className="text-[11.5px] font-bold text-[#3E8FBF] bg-[#D6EEF9]/60 px-3 py-1 rounded-full">
            آخر 7 أيام
          </span>
        </div>

        {/* Chart Area */}
        <div className="mt-8 h-56 flex items-end justify-between gap-3 sm:gap-6 px-2">
          {loading ? (
            <div className="w-full flex items-center justify-center h-full text-sm text-[#5B6B7A]">
              جاري تحميل بيانات الركاب...
            </div>
          ) : (
            data.map((item, idx) => {
              const heightPercent = Math.max(12, Math.round((item.count / maxCount) * 100));
              return (
                <div key={idx} className="flex-1 flex flex-col items-center gap-2 group h-full justify-end">
                  {/* Tooltip on hover */}
                  <span className="opacity-0 group-hover:opacity-100 transition-opacity text-[11px] font-bold text-white bg-[#1F2937] px-2 py-0.5 rounded-md shadow-md -mb-1">
                    {item.count}
                  </span>

                  {/* Bar */}
                  <div className="w-full max-w-[42px] bg-slate-100 rounded-xl overflow-hidden flex items-end h-40">
                    <div
                      className="w-full rounded-xl transition-all duration-700 ease-out group-hover:brightness-110"
                      style={{
                        height: `${heightPercent}%`,
                        background: 'linear-gradient(180deg, #7EC8E3 0%, #3E8FBF 100%)',
                        boxShadow: '0 4px 12px rgba(126, 200, 227, 0.4)',
                      }}
                    />
                  </div>

                  {/* Day label */}
                  <span className="text-[12px] font-semibold text-[#5B6B7A] mt-1">
                    {item.dayName}
                  </span>
                </div>
              );
            })
          )}
        </div>
      </div>

      <div className="mt-4 pt-3 border-t border-slate-100 flex items-center justify-between text-[11.5px] text-[#5B6B7A]">
        <span>إجمالي تأكيدات الحضور لهذا الأسبوع: {data.reduce((s, d) => s + d.count, 0)} راكب</span>
        <span className="text-[#2E9E5B] font-semibold">تحديث لحظي</span>
      </div>
    </div>
  );
};
