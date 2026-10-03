import React, { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CalendarClock, CheckCircle2, Clock3, DollarSign, RotateCcw, Search, ShieldAlert, Undo2, XCircle } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useAdminScope } from '../lib/adminScope';

// ── Types ───────────────────────────────────────────────────────────
interface ReportRow {
  id: string; student_name: string; phone: string; university: string | null; company: string; line: string;
  type: string; period: string; academic_year: number | null; label: string | null; status: string;
  phase: 'current' | 'upcoming' | 'expired'; paid: boolean; amount: number | null; price: number;
  paid_at: string | null; start_date: string | null; end_date: string | null; payment_method: string | null;
}
interface Totals {
  count: number; paid: number; unpaid: number; upcoming: number; upcoming_paid: number; expired: number;
  revenue: number; revenue_first: number; revenue_second: number; revenue_summer: number; revenue_annual: number; revenue_daily: number;
}
interface Report { baseline: string | null; totals: Totals; rows: ReportRow[] }
interface ResetRow { id: string; scope: 'financial' | 'all'; reset_at: string; note: string | null; undone_at: string | null }
interface Option { id: string; name: string }

const PERIODS: Record<string, string> = {
  first: 'الفصل الأول', second: 'الفصل الثاني', summer: 'الفصل الصيفي', annual: 'سنوي', daily: 'يومي (كاش)',
};
const PHASES: Record<string, string> = { current: 'ساري', upcoming: 'قادم (مدفوع مقدماً)', expired: 'منتهي' };
const money = (n: number | null | undefined) => `${Number(n || 0).toLocaleString('ar-EG')} ج.م`;
const date = (d: string | null) => (d ? new Date(d).toLocaleDateString('ar-EG') : '—');

export const ReportsPage: React.FC = () => {
  const admin = useAdminScope();
  const isSuper = admin.role === 'super_admin';
  const [report, setReport] = useState<Report | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filters, setFilters] = useState({
    period: '', academic_year: '', company_id: '', university_id: '', line_id: '', payment: '', phase: '', search: '',
    include_before_reset: false,
  });
  const [companies, setCompanies] = useState<Option[]>([]);
  const [universities, setUniversities] = useState<Option[]>([]);
  const [lines, setLines] = useState<(Option & { company_id: string })[]>([]);
  const [resets, setResets] = useState<ResetRow[]>([]);
  const [resetScope, setResetScope] = useState<'financial' | 'all' | null>(null);

  const load = async () => {
    setLoading(true);
    setError('');
    const { data, error: rpcError } = await supabase.rpc('admin_subscription_report', { p_filters: filters });
    if (rpcError) setError(rpcError.message);
    else setReport(data as Report);
    setLoading(false);
  };

  const loadOptions = async () => {
    const [{ data: c }, { data: u }, { data: l }, { data: r }] = await Promise.all([
      supabase.from('companies').select('id, name').order('name'),
      supabase.from('universities').select('id, name').order('name'),
      supabase.from('lines').select('id, name, company_id').order('name'),
      supabase.from('report_resets').select('id, scope, reset_at, note, undone_at').order('reset_at', { ascending: false }).limit(10),
    ]);
    setCompanies(c || []);
    setUniversities(u || []);
    setLines(l || []);
    setResets((r || []) as ResetRow[]);
  };

  useEffect(() => { void loadOptions(); }, []);
  // Debounce the search box; other filters apply immediately.
  useEffect(() => {
    const t = setTimeout(() => { void load(); }, filters.search ? 350 : 0);
    return () => clearTimeout(t);
  }, [filters]);

  const set = (patch: Partial<typeof filters>) => setFilters((f) => ({ ...f, ...patch }));
  const t = report?.totals;
  const years = useMemo(() => { const y = new Date().getFullYear(); return [y - 1, y, y + 1]; }, []);
  const activeResets = resets.filter((r) => !r.undone_at);
  const select = 'rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm';

  const undo = async (reset: ResetRow) => {
    if (!confirm('إلغاء هذا التصفير؟ ستعود التقارير لاحتساب البيانات السابقة له.')) return;
    const { error: undoError } = await supabase.rpc('admin_undo_report_reset', { p_reset_id: reset.id });
    if (undoError) alert(undoError.message);
    else { await loadOptions(); await load(); }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-slate-800">التقارير المالية والاشتراكات</h1>
          <p className="text-sm text-slate-500">
            الإيرادات محسوبة من الدفعات الفعلية (دفعة واحدة لكل اشتراك).
            {report?.baseline && !filters.include_before_reset && <> · بداية الاحتساب: <b>{new Date(report.baseline).toLocaleString('ar-EG')}</b></>}
          </p>
        </div>
        {isSuper && (
          <div className="flex gap-2">
            <button onClick={() => setResetScope('financial')} className="flex items-center gap-2 rounded-xl border border-amber-300 bg-amber-50 px-4 py-2 text-sm font-bold text-amber-800 hover:bg-amber-100">
              <RotateCcw className="h-4 w-4" /> تصفير البيانات المالية
            </button>
            <button onClick={() => setResetScope('all')} className="flex items-center gap-2 rounded-xl border border-rose-300 bg-rose-50 px-4 py-2 text-sm font-bold text-rose-700 hover:bg-rose-100">
              <ShieldAlert className="h-4 w-4" /> تصفير كل البيانات
            </button>
          </div>
        )}
      </div>

      {/* Totals */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Stat icon={<DollarSign className="h-5 w-5" />} color="emerald" title="إجمالي الإيرادات" value={t ? money(t.revenue) : '—'} />
        <Stat icon={<CheckCircle2 className="h-5 w-5" />} color="blue" title="اشتراكات مدفوعة" value={t ? `${t.paid}` : '—'} />
        <Stat icon={<XCircle className="h-5 w-5" />} color="rose" title="غير مدفوعة" value={t ? `${t.unpaid}` : '—'} />
        <Stat icon={<CalendarClock className="h-5 w-5" />} color="purple" title="قادمة (مدفوعة مقدماً)" value={t ? `${t.upcoming_paid} / ${t.upcoming}` : '—'} />
      </div>
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Revenue title="الفصل الأول" value={t?.revenue_first} onClick={() => set({ period: 'first', payment: 'paid' })} />
        <Revenue title="الفصل الثاني" value={t?.revenue_second} onClick={() => set({ period: 'second', payment: 'paid' })} />
        <Revenue title="سنوي" value={t?.revenue_annual} onClick={() => set({ period: 'annual', payment: 'paid' })} />
        <Revenue title="الفصل الصيفي" value={t?.revenue_summer} onClick={() => set({ period: 'summer', payment: 'paid' })} />
        <Revenue title="يومي (كاش)" value={t?.revenue_daily} onClick={() => set({ period: 'daily', payment: 'paid' })} />
      </div>

      {/* Filters */}
      <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm">
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-8">
          <label className="relative sm:col-span-2">
            <Search className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
            <input value={filters.search} onChange={(e) => set({ search: e.target.value })} placeholder="بحث باسم الطالب أو الهاتف" className={`${select} w-full pr-9`} />
          </label>
          <select value={filters.period} onChange={(e) => set({ period: e.target.value })} className={select} aria-label="الفترة">
            <option value="">كل الفترات</option>{Object.entries(PERIODS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          <select value={filters.academic_year} onChange={(e) => set({ academic_year: e.target.value })} className={select} aria-label="العام الدراسي">
            <option value="">كل الأعوام</option>{years.map((y) => <option key={y} value={y}>{y}/{y + 1}</option>)}
          </select>
          <select value={filters.payment} onChange={(e) => set({ payment: e.target.value })} className={select} aria-label="الدفع">
            <option value="">مدفوع وغير مدفوع</option><option value="paid">مدفوع</option><option value="unpaid">غير مدفوع</option>
          </select>
          <select value={filters.phase} onChange={(e) => set({ phase: e.target.value })} className={select} aria-label="الحالة">
            <option value="">كل الحالات</option>{Object.entries(PHASES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
          {isSuper && (
            <select value={filters.company_id} onChange={(e) => set({ company_id: e.target.value, line_id: '' })} className={select} aria-label="الشركة">
              <option value="">كل الشركات</option>{companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          )}
          <select value={filters.university_id} onChange={(e) => set({ university_id: e.target.value })} className={select} aria-label="الجامعة">
            <option value="">كل الجامعات</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
          </select>
          <select value={filters.line_id} onChange={(e) => set({ line_id: e.target.value })} className={select} aria-label="الخط">
            <option value="">كل الخطوط</option>
            {lines.filter((l) => !filters.company_id || l.company_id === filters.company_id).map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </select>
        </div>
        <div className="mt-3 flex flex-wrap items-center justify-between gap-2 text-xs text-slate-500">
          <label className="flex items-center gap-2">
            <input type="checkbox" checked={filters.include_before_reset} onChange={(e) => set({ include_before_reset: e.target.checked })} />
            عرض السجل الكامل (بما فيه ما قبل آخر تصفير)
          </label>
          <button onClick={() => setFilters({ period: '', academic_year: '', company_id: '', university_id: '', line_id: '', payment: '', phase: '', search: '', include_before_reset: false })} className="underline">مسح الفلاتر</button>
        </div>
      </div>

      {error && <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">تعذر تحميل التقرير: {error}</div>}

      {/* Rows */}
      <div className="overflow-hidden rounded-2xl border border-slate-100 bg-white shadow-sm">
        <div className="flex items-center justify-between border-b border-slate-100 p-4">
          <h2 className="font-bold text-slate-700">الطلاب والاشتراكات</h2>
          <span className="text-xs text-slate-400">{t ? `${t.count} اشتراك` : ''}{t && t.count > 2000 ? ' (يُعرض أول 2000)' : ''}</span>
        </div>
        {loading ? <div className="flex h-40 items-center justify-center text-slate-500">جاري التحميل...</div> : !report || report.rows.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا توجد اشتراكات مطابقة.</div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-right text-sm">
              <thead className="bg-slate-50 text-xs text-slate-500">
                <tr><th className="p-3">الطالب</th><th className="p-3">الشركة / الخط</th><th className="p-3">الفترة</th><th className="p-3">الدفع</th><th className="p-3">المبلغ المدفوع</th><th className="p-3">تاريخ الدفع</th><th className="p-3">الصلاحية</th><th className="p-3">الحالة</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {report.rows.map((r) => (
                  <tr key={r.id} className="hover:bg-slate-50/70">
                    <td className="p-3"><div className="font-bold text-slate-800">{r.student_name}</div><div className="font-mono text-xs text-slate-400">{r.phone}</div><div className="text-xs text-slate-400">{r.university}</div></td>
                    <td className="p-3 text-xs"><div className="font-semibold text-slate-700">{r.company}</div><div className="text-slate-500">{r.line}</div></td>
                    <td className="p-3 text-xs"><span className="rounded-lg bg-indigo-50 px-2 py-1 font-bold text-indigo-700">{PERIODS[r.period] ?? r.period}</span>{r.academic_year && <div className="mt-1 text-slate-400">{r.academic_year}/{r.academic_year + 1}</div>}</td>
                    <td className="p-3">{r.paid
                      ? <span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 px-2 py-1 text-xs font-bold text-emerald-700"><CheckCircle2 className="h-3 w-3" />مدفوع</span>
                      : <span className="inline-flex items-center gap-1 rounded-full bg-rose-50 px-2 py-1 text-xs font-bold text-rose-600"><Clock3 className="h-3 w-3" />{r.status === 'pending_review' ? 'إيصال قيد المراجعة' : r.status === 'rejected' ? 'إيصال مرفوض' : 'غير مدفوع'}</span>}
                      {r.payment_method && <div className="mt-1 text-[11px] text-slate-400">{r.payment_method}</div>}</td>
                    <td className="p-3 font-bold text-emerald-700">{r.paid ? money(r.amount) : <span className="text-slate-400">{money(r.price)} مستحق</span>}</td>
                    <td className="p-3 text-xs text-slate-600">{date(r.paid_at)}</td>
                    <td className="p-3 text-xs text-slate-600">{date(r.start_date)} ← {date(r.end_date)}</td>
                    <td className="p-3 text-xs"><span className={`rounded-full px-2 py-1 font-bold ${r.phase === 'current' ? 'bg-blue-50 text-blue-700' : r.phase === 'upcoming' ? 'bg-purple-50 text-purple-700' : 'bg-slate-100 text-slate-500'}`}>{PHASES[r.phase]}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {isSuper && resets.length > 0 && (
        <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm">
          <h3 className="mb-2 text-sm font-bold text-slate-700">سجل التصفير</h3>
          <ul className="space-y-1 text-xs text-slate-600">
            {resets.map((r) => (
              <li key={r.id} className="flex items-center justify-between gap-2 rounded-lg bg-slate-50 px-3 py-2">
                <span>{r.scope === 'all' ? 'تصفير كل البيانات' : 'تصفير البيانات المالية'} · {new Date(r.reset_at).toLocaleString('ar-EG')}{r.note ? ` · ${r.note}` : ''}{r.undone_at ? ' · (أُلغي)' : ''}</span>
                {!r.undone_at && <button onClick={() => void undo(r)} className="flex items-center gap-1 font-bold text-blue-600"><Undo2 className="h-3 w-3" />إلغاء</button>}
              </li>
            ))}
          </ul>
        </div>
      )}

      {resetScope && (
        <ResetDialog scope={resetScope} active={activeResets.length > 0}
          onClose={() => setResetScope(null)}
          onDone={async () => { setResetScope(null); await loadOptions(); await load(); }} />
      )}
    </div>
  );
};

const STAT_COLORS: Record<string, string> = {
  emerald: 'bg-emerald-50 text-emerald-600', blue: 'bg-blue-50 text-blue-600',
  rose: 'bg-rose-50 text-rose-600', purple: 'bg-purple-50 text-purple-600',
};

const Stat: React.FC<{ icon: React.ReactNode; color: string; title: string; value: string }> = ({ icon, color, title, value }) => (
  <div className="rounded-2xl border border-slate-100 bg-white p-4 shadow-sm">
    <div className="flex items-center gap-3">
      <div className={`rounded-xl p-2.5 ${STAT_COLORS[color]}`}>{icon}</div>
      <div><p className="text-xs font-semibold text-slate-400">{title}</p><p className="text-xl font-bold text-slate-800">{value}</p></div>
    </div>
  </div>
);

const Revenue: React.FC<{ title: string; value?: number; onClick: () => void }> = ({ title, value, onClick }) => (
  <button onClick={onClick} className="rounded-2xl border border-slate-100 bg-white p-4 text-right shadow-sm hover:border-emerald-200" title="عرض الطلاب الذين دفعوا">
    <p className="text-xs font-semibold text-slate-400">إيرادات {title}</p>
    <p className="text-lg font-bold text-emerald-700">{money(value)}</p>
  </button>
);

// ── Reset confirmation (dashboard only — nothing is deleted) ─────────
const ResetDialog: React.FC<{ scope: 'financial' | 'all'; active: boolean; onClose: () => void; onDone: () => void }> = ({ scope, onClose, onDone }) => {
  const phrase = scope === 'all' ? 'RESET ALL DATA' : 'RESET FINANCIAL DATA';
  const [typed, setTyped] = useState('');
  const [ack, setAck] = useState(false);
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const run = async () => {
    setBusy(true);
    setError('');
    const { error: rpcError } = await supabase.rpc('admin_reset_reports', { p_scope: scope, p_confirm: typed, p_note: note || null });
    setBusy(false);
    if (rpcError) setError(rpcError.message);
    else onDone();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-900/40 p-4" dir="rtl">
      <div className="w-full max-w-lg space-y-4 rounded-3xl bg-white p-6 shadow-2xl">
        <div className="flex items-center gap-2 text-lg font-bold text-rose-700"><AlertTriangle className="h-5 w-5" />{scope === 'all' ? 'تصفير كل البيانات في لوحة التحكم' : 'تصفير البيانات المالية'}</div>
        <div className="space-y-2 rounded-2xl bg-slate-50 p-4 text-sm leading-relaxed text-slate-700">
          <p><b>لن يُحذف أي شيء من قاعدة البيانات.</b> التصفير يحدد لحظة بداية جديدة لحساب الأرقام في لوحة التحكم فقط.</p>
          <p>بعد التصفير تبدأ التقارير المالية من الصفر: الإيرادات وأعداد الاشتراكات المدفوعة وغير المدفوعة تحسب ما يحدث بعد هذه اللحظة فقط{scope === 'all' ? '، وكذلك أرقام النظرة العامة' : ''}.</p>
          <p>تبقى كل الاشتراكات والإيصالات وصورها وحسابات الطلاب والخطوط ووسائل الدفع كما هي، ويمكن رؤية السجل الكامل من خيار «عرض السجل الكامل»، ويمكن إلغاء التصفير لاحقاً من سجل التصفير.</p>
        </div>
        <label className="flex items-start gap-2 text-sm text-slate-700">
          <input type="checkbox" checked={ack} onChange={(e) => setAck(e.target.checked)} className="mt-1" />
          فهمت أن أرقام لوحة التحكم ستبدأ من الصفر.
        </label>
        <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="سبب التصفير (اختياري)، مثال: بداية الفصل الثاني" className="w-full rounded-xl border border-slate-200 px-3 py-2 text-sm" />
        <label className="block text-sm text-slate-600">للتأكيد اكتب: <code className="rounded bg-rose-50 px-1.5 py-0.5 font-bold text-rose-700" dir="ltr">{phrase}</code>
          <input value={typed} onChange={(e) => setTyped(e.target.value)} dir="ltr" autoComplete="off" className="mt-1 w-full rounded-xl border border-slate-200 px-3 py-2 font-mono text-sm" />
        </label>
        {error && <p role="alert" className="rounded-xl bg-rose-50 px-3 py-2 text-sm text-rose-700">{error}</p>}
        <div className="flex justify-end gap-2">
          <button onClick={onClose} className="rounded-xl border border-slate-200 px-4 py-2 text-sm font-bold text-slate-600">إلغاء</button>
          <button onClick={() => void run()} disabled={busy || !ack || typed !== phrase}
            className="rounded-xl bg-rose-600 px-5 py-2 text-sm font-bold text-white disabled:opacity-40">{busy ? 'جاري التصفير...' : 'تأكيد التصفير'}</button>
        </div>
      </div>
    </div>
  );
};
