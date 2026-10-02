import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Topbar } from '../components/Topbar';
import { StatsRow } from '../components/StatsRow';
import { WeeklyRidersChart } from '../components/WeeklyRidersChart';
import { TopLinesPanel } from '../components/TopLinesPanel';
import { PendingReceiptsTable } from '../components/PendingReceiptsTable';
import { usePendingReceipts } from '../lib/pendingReceipts';

const cairoDateParts = new Intl.DateTimeFormat('en-GB', {
  timeZone: 'Africa/Cairo',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

function cairoDateKey(date: Date): string {
  const parts = Object.fromEntries(cairoDateParts.formatToParts(date).map(({ type, value }) => [type, value]));
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function shiftDateKey(dateKey: string, days: number): string {
  const [year, month, day] = dateKey.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

function cairoWeekdayName(dateKey: string): string {
  const [year, month, day] = dateKey.split('-').map(Number);
  const daysArabic = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  return daysArabic[new Date(Date.UTC(year, month - 1, day)).getUTCDay()];
}

async function loadAll<T>(loadPage: (from: number, to: number) => Promise<{ data: T[] | null; error: { message: string } | null }>): Promise<T[]> {
  const rows: T[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await loadPage(offset, offset + 999);
    if (error) throw new Error(error.message);
    const page = data || [];
    rows.push(...page);
    if (page.length < 1000) return rows;
  }
}

export const OverviewPage: React.FC = () => {
  const [stats, setStats] = useState({
    activeStudents: 0,
    ridingToday: null as number | null,
    companiesCount: 0,
    monthlyRevenue: 0,
  });
  const [weeklyData, setWeeklyData] = useState<{ dayName: string; dateStr: string; count: number }[]>([]);
  const [weeklyError, setWeeklyError] = useState('');
  const [topLines, setTopLines] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const {
    receipts: pendingReceipts,
    loading: receiptsLoading,
    error: receiptsError,
    refresh: refreshPendingReceipts,
  } = usePendingReceipts();

  useEffect(() => {
    fetchDashboardData();
  }, []);

  const fetchDashboardData = async () => {
    let weeklyQueryAttempted = false;
    try {
      setLoading(true);

      // 1. Stats Queries
      // Active subscriptions count
      const [activeSubs, archivedRevenue] = await Promise.all([
        loadAll(async (from, to) => await supabase.from('subscriptions').select('line_id,student_id,price,status')
          .eq('status', 'active').range(from, to)),
        loadAll(async (from, to) => await supabase.from('deleted_student_revenue').select('amount').range(from, to)),
      ]);
      const totalRevenue =
        activeSubs.reduce((sum, item: any) => sum + Number(item.price || 0), 0) +
        archivedRevenue.reduce((sum, item: any) => sum + Number(item.amount || 0), 0);

      // Companies count
      const { count: compCount } = await supabase
        .from('companies')
        .select('*', { count: 'exact', head: true })
        .eq('is_active', true);

      // Use calendar dates in the application's Cairo timezone. UTC ISO dates
      // can roll over to tomorrow while it is still today in Egypt.
      const todayStr = cairoDateKey(new Date());
      let ridersTodayCount: number | null = null;

      // Read exact counts for each date from the same source as the student
      // "نازل بكرة" confirmations. Never invent values when a day is empty.
      try {
        weeklyQueryAttempted = true;
        setWeeklyError('');
        const dateKeys = Array.from({ length: 7 }, (_, offset) => shiftDateKey(todayStr, offset - 6));
        const weekPoints = await Promise.all(dateKeys.map(async (dateStr) => {
          const { count, error } = await supabase
            .from('daily_ride_status')
            .select('student_id', { count: 'exact', head: true })
            .eq('ride_date', dateStr)
            .eq('is_riding', true);
          if (error) throw error;
          if (count === null) throw new Error(`The exact rider count was not returned for ${dateStr}.`);

          return {
            dateStr,
            dayName: cairoWeekdayName(dateStr),
            count,
          };
        }));
        setWeeklyData(weekPoints);
        ridersTodayCount = weekPoints[weekPoints.length - 1]?.count ?? null;
      } catch (weeklyLoadError) {
        console.error('Error fetching exact weekly rider confirmations:', weeklyLoadError);
        setWeeklyData([]);
        setWeeklyError('تعذر تحميل أعداد الركاب الفعلية من قاعدة البيانات.');
      }

      // Riding Today uses the exact same daily row count as the chart. Keep it
      // unavailable if the database could not provide an exact count.

      setStats({
        activeStudents: activeSubs.length,
        ridingToday: ridersTodayCount,
        companiesCount: compCount || 0,
        monthlyRevenue: totalRevenue || 0,
      });

      // 2. Top Lines Query
      const { data: linesData, error: linesError } = await supabase
        .from('lines')
        .select('id,name,is_active,companies(name)')
        .order('name');
      if (linesError) throw linesError;

      const topLineSubs = await loadAll(async (from, to) => await supabase.from('subscriptions')
        .select('line_id,status').eq('status', 'active').range(from, to));
      const activeCountByLine = new Map<string, number>();
      for (const subscription of topLineSubs as any[]) {
        activeCountByLine.set(subscription.line_id, (activeCountByLine.get(subscription.line_id) || 0) + 1);
      }

      const formattedTopLines = (linesData || []).map((l: any) => {
        const activeSubscribers = activeCountByLine.get(l.id) || 0;
        return {
          id: l.id,
          name: l.name,
          companyName: l.companies?.name || '—',
          subscriberCount: activeSubscribers,
          isActive: l.is_active,
        };
      }).sort((a, b) => b.subscriberCount - a.subscriberCount);

      setTopLines(formattedTopLines);

    } catch (err) {
      console.error('Error fetching admin overview data:', err);
      if (!weeklyQueryAttempted) {
        setWeeklyData([]);
        setWeeklyError('تعذر تحميل أعداد الركاب الفعلية من قاعدة البيانات.');
      }
    } finally {
      setLoading(false);
    }
  };

  // Optimistic handler when a receipt is approved or rejected
  const handleReceiptReviewed = (receiptId: string) => {
    void receiptId;
    void refreshPendingReceipts();
    void fetchDashboardData();
  };

  return (
    <div className="space-y-6">
      <Topbar
        title="لوحة المتابعة والتحكم العامة"
        subtitle="متابعة الحضور المباشر، الإيرادات، وتأكيد اشتراكات الطلاب"
      />

      {/* 4 Stats Cards */}
      <StatsRow
        activeStudents={stats.activeStudents}
        ridingToday={stats.ridingToday}
        companiesCount={stats.companiesCount}
        monthlyRevenue={stats.monthlyRevenue}
        loading={loading}
      />

      {/* Two-Column Row: Weekly Chart (Left) + Top Lines (Right) */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
        <div className="lg:col-span-7">
          <WeeklyRidersChart data={weeklyData} loading={loading} error={weeklyError} />
        </div>
        <div className="lg:col-span-5">
          <TopLinesPanel lines={topLines} loading={loading} />
        </div>
      </div>

      {/* Full-Width Pending Receipts Panel */}
      <div>
        {receiptsError ? (
          <div role="alert" className="glass-panel p-6 text-rose-700">
            تعذر تحميل الإيصالات: {receiptsError}
            <button className="mr-3 font-bold underline" onClick={fetchDashboardData}>إعادة المحاولة</button>
          </div>
        ) : (
            <PendingReceiptsTable receipts={pendingReceipts} loading={loading || receiptsLoading} onReceiptReviewed={handleReceiptReviewed} />
        )}
      </div>
    </div>
  );
};
