import React from 'react';
import { Bus, FileCheck2, Users, Wallet } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { count, egp, StatsRow } from '../components/StatsRow';
import { WeeklyRidersChart } from '../components/WeeklyRidersChart';
import { TopLinesPanel } from '../components/TopLinesPanel';
import { PendingReceiptsTable } from '../components/PendingReceiptsTable';
import { useCompany } from '../lib/adminScope';
import { ridersCard, useCompanyOverview, weekPoints } from '../lib/overview';
import { usePendingReceipts } from '../lib/pendingReceipts';

/** One company at a glance. Every number here is this company's and nobody else's. */
export const OverviewPage: React.FC = () => {
  const company = useCompany();
  const { data, loading, error, refresh } = useCompanyOverview(company.id);
  const receipts = usePendingReceipts(company.id);

  const riders = ridersCard(data ?? null, 'حسب تأكيدات الطلاب في التطبيق');
  return (
    <div className="space-y-6">
      <Topbar title={`نظرة عامة — ${company.name}`} subtitle="الحضور، الإيرادات واعتماد الاشتراكات، محدّثة لحظياً" />

      {error && (
        <div role="alert" className="glass-panel p-4 text-sm text-rose-700">
          تعذر تحميل الأرقام: {error}
          <button className="mr-3 font-bold underline" onClick={() => void refresh()}>إعادة المحاولة</button>
        </div>
      )}

      <StatsRow
        loading={loading}
        cards={[
          { label: 'الاشتراكات السارية اليوم', value: count(data?.active_subscriptions ?? 0), hint: `${count(data?.members ?? 0)} طالب مسجل في الشركة`, icon: Users, tone: 'blue' },
          { label: riders.label, value: count(riders.value), hint: riders.hint, icon: Bus, tone: 'green' },
          { label: 'إيصالات بانتظار المراجعة', value: count(data?.pending_receipts ?? 0), hint: 'تظهر أسفل الصفحة فور وصولها', icon: FileCheck2, tone: 'amber' },
          { label: 'إجمالي الإيرادات المسجلة', value: egp(Number(data?.revenue ?? 0)), hint: data?.baseline ? 'منذ آخر تصفير للتقارير' : 'كل الاشتراكات المدفوعة', icon: Wallet, tone: 'blue' },
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
              id: line.id, name: line.name, companyName: company.name, subscriberCount: line.subscribers, isActive: line.is_active,
            }))}
          />
        </div>
      </div>

      {receipts.error ? (
        <div role="alert" className="glass-panel p-6 text-rose-700">
          تعذر تحميل الإيصالات: {receipts.error}
          <button className="mr-3 font-bold underline" onClick={() => void receipts.refresh()}>إعادة المحاولة</button>
        </div>
      ) : (
        <PendingReceiptsTable
          receipts={receipts.receipts}
          loading={receipts.loading}
          onReview={receipts.review}
        />
      )}
    </div>
  );
};
