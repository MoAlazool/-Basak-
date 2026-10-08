import React from 'react';
import { Skeleton } from '../components/Skeleton';
import { Link } from 'react-router-dom';
import { Building2, Bus, FileCheck2, Users, Wallet } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { count, egp, StatsRow } from '../components/StatsRow';
import { WeeklyRidersChart } from '../components/WeeklyRidersChart';
import { TopLinesPanel } from '../components/TopLinesPanel';
import { PasswordResetRequests } from '../components/PasswordResetRequests';
import { companyStatusLabel } from '../lib/adminScope';
import { ridersCard, usePlatformOverview, weekPoints } from '../lib/overview';

/** The whole platform: totals across companies, then each company side by side. */
export const PlatformOverviewPage: React.FC = () => {
  const { data, loading, error, refresh } = usePlatformOverview();
  const rows = [...(data?.per_company ?? [])].sort((a, b) => Number(b.revenue) - Number(a.revenue));

  const riders = ridersCard(data ?? null, `${count(data?.lines ?? 0)} خط • ${count(data?.supervisors ?? 0)} مشرف`);
  return (
    <div className="space-y-6">
      <Topbar title="نظرة عامة على المنصة" subtitle="إجمالي كل الشركات، محدّث لحظياً" />

      {error && (
        <div role="alert" className="glass-panel p-4 text-sm text-rose-700">
          تعذر تحميل الأرقام: {error}
          <button className="mr-3 font-bold underline" onClick={() => void refresh()}>إعادة المحاولة</button>
        </div>
      )}

      <StatsRow
        loading={loading}
        cards={[
          { label: 'شركات النقل', value: count(data?.companies.total ?? 0), hint: `${count(data?.companies.active ?? 0)} مفعّلة • ${count(data?.companies.suspended ?? 0)} موقوفة`, icon: Building2, tone: 'amber' },
          { label: 'الطلاب على المنصة', value: count(data?.students ?? 0), hint: `${count(data?.active_subscriptions ?? 0)} اشتراك سارٍ اليوم`, icon: Users, tone: 'blue' },
          { label: riders.label, value: count(riders.value), hint: riders.hint, icon: Bus, tone: 'green' },
          { label: 'إجمالي الإيرادات المسجلة', value: egp(Number(data?.revenue ?? 0)), hint: 'مجموع إيرادات الشركات، كلٌّ منذ آخر تصفير لها', icon: Wallet, tone: 'blue' },
        ]}
      />

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <div className="lg:col-span-7">
          <WeeklyRidersChart data={weekPoints(data?.riders_week)} loading={loading} error={error ? 'تعذر تحميل أعداد الركاب.' : ''} />
        </div>
        <div className="lg:col-span-5">
          <TopLinesPanel
            loading={loading}
            lines={(data?.top_lines ?? []).map((line) => ({
              id: line.id, name: line.name, companyName: line.company ?? '', subscriberCount: line.subscribers, isActive: line.is_active,
            }))}
          />
        </div>
      </div>

      {/* Every open request, including students who ride with no company and so have no company to ask. */}
      <PasswordResetRequests companyId={null} />

      <div className="glass-panel overflow-hidden">
        <div className="flex items-center justify-between gap-3 border-b border-slate-100 p-5">
          <div>
            <h2 className="text-[16px] font-bold text-[#1F2937]">مقارنة الشركات</h2>
            <p className="text-[12px] font-medium text-[#5B6B7A]">أرقام كل شركة على حدة. ادخل مساحة الشركة للتفاصيل.</p>
          </div>
          {(data?.pending_receipts ?? 0) > 0 && (
            <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-100 px-3 py-1 text-xs font-bold text-amber-800">
              <FileCheck2 className="h-3.5 w-3.5" /> {count(data!.pending_receipts)} إيصال بانتظار المراجعة
            </span>
          )}
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[760px] text-right text-sm">
            <thead className="bg-slate-50/60 text-[12px] text-slate-500">
              <tr>
                <th className="p-3 font-bold">الشركة</th>
                <th className="p-3 font-bold">الطلاب</th>
                <th className="p-3 font-bold">اشتراكات سارية</th>
                <th className="p-3 font-bold">نازلين اليوم</th>
                <th className="p-3 font-bold">إيصالات معلقة</th>
                <th className="p-3 font-bold">الخطوط</th>
                <th className="p-3 font-bold">الإيرادات</th>
                <th className="p-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {loading && Array.from({ length: 4 }, (_, r) => (
                <tr key={r} aria-busy="true">
                  {Array.from({ length: 8 }, (_, c) => (
                    <td key={c} className="p-3"><Skeleton className={`h-3.5 ${c === 0 ? 'w-28' : 'w-12'}`} /></td>
                  ))}
                </tr>
              ))}
              {!loading && rows.length === 0 && <tr><td colSpan={8} className="p-8 text-center text-slate-500">لا توجد شركات بعد.</td></tr>}
              {rows.map((row) => (
                <tr key={row.company.id} className="hover:bg-slate-50/70">
                  <td className="p-3">
                    <span className="font-bold text-slate-800">{row.company.name}</span>
                    {row.company.status !== 'active' && (
                      <span className="mr-2 rounded-full bg-amber-100 px-2 py-0.5 text-[10.5px] font-bold text-amber-800">{companyStatusLabel[row.company.status]}</span>
                    )}
                  </td>
                  <td className="p-3">{count(row.members)}</td>
                  <td className="p-3">{count(row.active_subscriptions)}</td>
                  <td className="p-3">{count(row.riders_today)}</td>
                  <td className="p-3">{row.pending_receipts > 0 ? <span className="font-bold text-amber-700">{count(row.pending_receipts)}</span> : '—'}</td>
                  <td className="p-3">{count(row.active_lines)} <span className="text-xs text-slate-400">/ {count(row.lines)}</span></td>
                  <td className="p-3 font-bold text-slate-800">{egp(Number(row.revenue))}</td>
                  <td className="p-3 text-left">
                    <Link to={`/c/${row.company.id}`} className="rounded-lg border border-[#BFE3F3] px-3 py-1.5 text-xs font-bold text-[#3E8FBF] hover:bg-[#EAF7FD]">دخول</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
