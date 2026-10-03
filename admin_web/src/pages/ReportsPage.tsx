import React, { useEffect, useState } from 'react';
import { TrendingUp, DollarSign, Users } from 'lucide-react';
import { supabase } from '../lib/supabase';

interface ReportRow {
  lineId: string;
  lineName: string;
  companyName: string;
  subscriberCount: number;
  totalRevenue: number;
  attendanceRate: number;
}

const cairoToday = () => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Africa/Cairo', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date());

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

export const ReportsPage: React.FC = () => {
  const [reports, setReports] = useState<ReportRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [attendanceRate, setAttendanceRate] = useState<number | null>(null);

  useEffect(() => { void fetchReportData(); }, []);

  const fetchReportData = async () => {
    try {
      setLoading(true);
      setError('');
      const today = cairoToday();
      const [{ data: lines, error: linesError }, subs, archived, rides] = await Promise.all([
        supabase.from('lines').select('id,name,company_id,companies(name)').order('name'),
        loadAll(async (from, to) => await supabase.from('subscriptions').select('line_id,student_id,price,status,created_at,start_date,end_date')
          .not('paid_at', 'is', null).range(from, to)),
        loadAll(async (from, to) => await supabase.from('deleted_student_revenue')
          .select('line_id,line_name,company_name,company_id,amount,archived_at')
          .range(from, to)),
        loadAll(async (from, to) => await supabase.from('daily_ride_status')
          .select('student_id,is_riding').eq('ride_date', today).eq('is_riding', true).range(from, to)),
      ]);
      if (linesError) throw new Error(linesError.message);

      const lineRows = lines || [];
      // Revenue: all paid subscriptions. Subscribers/attendance: those valid today.
      const paidSubs = subs;
      const currentSubs = paidSubs.filter((sub: any) => sub.status === 'active'
        && (!sub.start_date || sub.start_date <= today) && (!sub.end_date || sub.end_date >= today));
      const lineById = new Map(lineRows.map((line: any) => [line.id, line]));
      const rideStudents = new Set(rides.map((ride: any) => ride.student_id));
      const result: ReportRow[] = lineRows.map((line: any) => {
        const lineSubs = currentSubs.filter((sub: any) => sub.line_id === line.id);
        const linePaid = paidSubs.filter((sub: any) => sub.line_id === line.id);
        const attended = new Set(lineSubs.filter((sub: any) => rideStudents.has(sub.student_id)).map((sub: any) => sub.student_id));
        const archivedTotal = archived.filter((row: any) => row.line_id === line.id)
          .reduce((sum: number, row: any) => sum + Number(row.amount || 0), 0);
        return {
          lineId: line.id,
          lineName: line.name,
          companyName: line.companies?.name || '—',
          subscriberCount: lineSubs.length,
          totalRevenue: linePaid.reduce((sum: number, sub: any) => sum + Number(sub.price || 0), 0) + archivedTotal,
          attendanceRate: lineSubs.length ? Math.round((attended.size / lineSubs.length) * 100) : 0,
        };
      });

      const archivedByRemovedLine = new Map<string, { lineName: string; companyName: string; amount: number }>();
      for (const row of archived as any[]) {
        if (row.line_id && lineById.has(row.line_id)) continue;
        const key = row.line_id || `archived-${row.company_id || 'unknown'}`;
        const current = archivedByRemovedLine.get(key) || { lineName: row.line_name || 'خط محذوف', companyName: row.company_name || '—', amount: 0 };
        current.amount += Number(row.amount || 0);
        archivedByRemovedLine.set(key, current);
      }
      for (const [lineId, row] of archivedByRemovedLine) {
        result.push({ lineId: `archive-${lineId}`, lineName: row.lineName, companyName: row.companyName, subscriberCount: 0, totalRevenue: row.amount, attendanceRate: 0 });
      }

      const activeSubscriberCount = currentSubs.length;
      const attendedTotal = new Set(currentSubs.filter((sub: any) => rideStudents.has(sub.student_id)).map((sub: any) => sub.student_id)).size;
      setAttendanceRate(activeSubscriberCount ? Math.round((attendedTotal / activeSubscriberCount) * 100) : 0);
      setReports(result);
    } catch (loadError) {
      console.error('Error generating reports:', loadError);
      setReports([]);
      setAttendanceRate(null);
      setError(loadError instanceof Error ? loadError.message : 'تعذر تحميل بيانات التقارير.');
    } finally {
      setLoading(false);
    }
  };

  const totalRevenue = reports.reduce((sum, row) => sum + row.totalRevenue, 0);
  const totalSubscribers = reports.reduce((sum, row) => sum + row.subscriberCount, 0);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">تقارير التشغيل والإحصائيات</h1>
        <p className="text-sm text-slate-500">إيرادات الاشتراكات النشطة والسجل المؤرشف، وحضور اليوم من سجلات النظام.</p>
      </div>

      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل التقرير: {error}<button className="mr-3 underline" onClick={fetchReportData}>إعادة المحاولة</button></div>}

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"><div className="flex items-center gap-3"><div className="rounded-xl bg-emerald-50 p-3 text-emerald-600"><DollarSign className="h-6 w-6" /></div><div><p className="text-xs font-semibold text-slate-400">إجمالي الإيرادات المسجلة</p><h3 className="text-2xl font-bold text-slate-800">{loading ? '—' : `${totalRevenue.toLocaleString('ar-EG')} ج.م`}</h3></div></div></div>
        <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"><div className="flex items-center gap-3"><div className="rounded-xl bg-blue-50 p-3 text-blue-600"><Users className="h-6 w-6" /></div><div><p className="text-xs font-semibold text-slate-400">إجمالي الاشتراكات النشطة</p><h3 className="text-2xl font-bold text-slate-800">{loading ? '—' : `${totalSubscribers.toLocaleString('ar-EG')} اشتراك`}</h3></div></div></div>
        <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"><div className="flex items-center gap-3"><div className="rounded-xl bg-purple-50 p-3 text-purple-600"><TrendingUp className="h-6 w-6" /></div><div><p className="text-xs font-semibold text-slate-400">حضور اليوم بين مشتركي الشهر</p><h3 className="text-2xl font-bold text-slate-800">{loading || attendanceRate === null ? '—' : `${attendanceRate}%`}</h3></div></div></div>
      </div>

      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-hidden">
        <div className="border-b border-slate-100 p-5"><h2 className="text-base font-bold text-slate-700">الإيرادات والحضور الفعلي بحسب خط السير والشركة</h2></div>
        {loading ? <div className="flex h-40 items-center justify-center text-slate-500">جاري تحميل البيانات الفعلية...</div> : error ? null : reports.length === 0 ? <div className="p-8 text-center text-slate-500">لا توجد اشتراكات أو إيرادات مسجلة.</div> : (
          <div className="overflow-x-auto"><table className="w-full text-right text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500"><tr><th className="p-4 font-bold">اسم الخط</th><th className="p-4 font-bold">الشركة المشغلة</th><th className="p-4 font-bold">الاشتراكات النشطة</th><th className="p-4 font-bold">الإيراد المسجل</th><th className="p-4 font-bold">حضور اليوم</th></tr></thead>
            <tbody className="divide-y divide-slate-100">{reports.map((row) => <tr key={row.lineId} className="hover:bg-slate-50/80"><td className="p-4 font-semibold text-slate-800">{row.lineName}</td><td className="p-4 text-slate-600">{row.companyName}</td><td className="p-4 font-bold text-slate-800">{row.subscriberCount}</td><td className="p-4 font-bold text-emerald-600">{row.totalRevenue.toLocaleString('ar-EG')} ج.م</td><td className="p-4"><div className="flex items-center gap-2"><div className="h-2 w-24 overflow-hidden rounded-full bg-slate-100"><div className="h-full rounded-full bg-blue-500" style={{ width: `${row.attendanceRate}%` }} /></div><span className="text-xs font-semibold text-slate-600">{row.attendanceRate}%</span></div></td></tr>)}</tbody>
          </table></div>
        )}
      </div>
    </div>
  );
};
