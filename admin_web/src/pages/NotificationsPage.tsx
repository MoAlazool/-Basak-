import React, { useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useCompany } from '../lib/adminScope';
import { keys, usePageData } from '../lib/query';
import { SkeletonRows } from '../components/Skeleton';
import { Bell, Bus, Megaphone, Search, Send, Trash2, Users } from 'lucide-react';

interface SentNotification {
  id: string;
  title: string;
  body: string;
  created_at: string;
  sender_role: 'admin' | 'supervisor';
  sender_name: string;
  audience: string;
  line_id: string | null;
  students: number;
  read: number;
}

interface LineOption { id: string; name: string; is_active: boolean; }

/** Ready-made messages: [button, title, text]. */
const TEMPLATES: [string, string, string][] = [
  ['إجازة رسمية', 'إجازة رسمية', 'غداً إجازة رسمية ولا توجد رحلات. تعود الرحلات في مواعيدها بعد الإجازة.'],
  ['تعديل المواعيد', 'تعديل مواعيد الرحلات', 'تم تعديل مواعيد بعض الرحلات، راجع مواعيدك في التطبيق قبل التصويت.'],
  ['تذكير بالدفع', 'تذكير بسداد الاشتراك', 'اقترب موعد سداد الاشتراك. ادفع من صفحة الاشتراك في التطبيق لتستمر رحلاتك.'],
];

const FILTERS = [
  { key: 'all', label: 'الكل' },
  { key: 'admin', label: 'من الإدارة' },
  { key: 'supervisor', label: 'من المشرفين' },
] as const;

const when = (iso: string) =>
  new Date(iso).toLocaleString('ar-EG', { day: 'numeric', month: 'long', hour: 'numeric', minute: '2-digit' });

/**
 * Notifications to the company's students: written here (all students or one
 * line) or by supervisors from the app (their line or one trip of the day).
 * Everything sent appears below with how many students have read it.
 */
export const NotificationsPage: React.FC = () => {
  const companyId = useCompany().id;
  const [title, setTitle] = useState('');
  const [body, setBody] = useState('');
  const [lineId, setLineId] = useState('');
  const [sending, setSending] = useState(false);
  const [query, setQuery] = useState('');
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['key']>('all');

  const page = usePageData(keys.company(companyId, 'notifications'), async () => {
    const [sentRes, lineRes] = await Promise.all([
      supabase.rpc('get_company_notifications', { p_company_id: companyId }),
      supabase.from('lines').select('id, name, is_active').eq('company_id', companyId).order('name'),
    ]);
    if (sentRes.error) throw sentRes.error;
    if (lineRes.error) throw lineRes.error;
    return {
      sent: (sentRes.data || []) as SentNotification[],
      lines: (lineRes.data || []) as LineOption[],
    };
  });
  const sent = page.data?.sent ?? [];
  const lines = page.data?.lines ?? [];

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    return sent.filter((n) => (filter === 'all' || n.sender_role === filter)
      && (!q || [n.title, n.body, n.sender_name, n.audience].some((field) => field.toLowerCase().includes(q))));
  }, [sent, query, filter]);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim() || !body.trim()) {
      alert('اكتب عنوان الإشعار ونصه.');
      return;
    }
    try {
      setSending(true);
      const { data, error } = await supabase.rpc('send_notification', {
        p_title: title.trim(),
        p_body: body.trim(),
        p_company_id: companyId,
        p_line_id: lineId || null,
      });
      if (error) throw error;
      setTitle('');
      setBody('');
      await page.reload();
      alert(`تم إرسال الإشعار إلى ${(data as { students?: number } | null)?.students ?? 0} طالب.`);
    } catch (err: any) {
      alert('فشل إرسال الإشعار: ' + err.message);
    } finally {
      setSending(false);
    }
  };

  const handleDelete = async (n: SentNotification) => {
    if (!confirm(`حذف الإشعار "${n.title}"؟ سيختفي من عند كل الطلاب والمشرفين.`)) return;
    const { error } = await supabase.rpc('delete_notification', { p_id: n.id });
    if (error) alert('فشل الحذف: ' + error.message);
    else void page.reload();
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">الإشعارات</h1>
        <p className="text-sm text-slate-500">
          أرسل إشعاراً لكل طلاب الشركة أو لطلاب خط واحد. يرسل المشرفون أيضاً من التطبيق لطلاب خطهم أو لركاب رحلة اليوم، ويظهر كل ما أُرسل هنا.
        </p>
      </div>

      {page.error && (
        <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
          تعذر تحميل الإشعارات: {page.error}
          <button className="mr-3 font-bold underline" onClick={() => void page.reload()}>إعادة المحاولة</button>
        </div>
      )}

      {/* Compose */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
          <Megaphone className="h-4 w-4 text-blue-600" />
          إشعار جديد
        </h2>
        <form onSubmit={handleSend} className="mt-4 space-y-4">
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            <div>
              <label className="text-xs font-semibold text-slate-500">يصل إلى</label>
              <select value={lineId} onChange={(e) => setLineId(e.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 bg-white px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none">
                <option value="">كل طلاب الشركة</option>
                {lines.map((line) => (
                  <option key={line.id} value={line.id}>طلاب {line.name}{!line.is_active && ' (موقوف)'}</option>
                ))}
              </select>
            </div>
            <div className="md:col-span-2">
              <label className="text-xs font-semibold text-slate-500">العنوان ({title.length}/80)</label>
              <input type="text" maxLength={80} placeholder="مثال: إجازة رسمية" value={title}
                onChange={(e) => setTitle(e.target.value)}
                className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" />
            </div>
          </div>
          <div>
            <label className="text-xs font-semibold text-slate-500">نص الإشعار ({body.length}/600)</label>
            <textarea maxLength={600} rows={3} placeholder="اكتب ما تريد أن يعرفه الطلاب" value={body}
              onChange={(e) => setBody(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" />
          </div>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-xs font-semibold text-slate-500">رسائل جاهزة:</span>
              {TEMPLATES.map(([label, t, b]) => (
                <button key={label} type="button" onClick={() => { setTitle(t); setBody(b); }}
                  className="rounded-full bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700 transition hover:bg-blue-100">
                  {label}
                </button>
              ))}
            </div>
            <button type="submit" disabled={sending || !title.trim() || !body.trim()}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50">
              <Send className="h-4 w-4" />
              {sending ? 'جاري الإرسال...' : 'إرسال الإشعار'}
            </button>
          </div>
        </form>
      </div>

      {/* Sent */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm">
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 p-4">
          <div className="flex flex-wrap gap-2">
            {FILTERS.map((f) => (
              <button key={f.key} onClick={() => setFilter(f.key)}
                className={`rounded-full px-3 py-1 text-xs font-bold transition ${
                  filter === f.key ? 'bg-blue-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                {f.label}
              </button>
            ))}
          </div>
          <div className="relative w-full sm:w-64">
            <Search className="absolute right-3 top-2.5 h-4 w-4 text-slate-400" />
            <input type="search" placeholder="ابحث في الإشعارات" value={query} onChange={(e) => setQuery(e.target.value)}
              className="w-full rounded-xl border border-slate-200 py-2 pl-3 pr-9 text-sm focus:border-blue-500 focus:outline-none" />
          </div>
        </div>

        {page.loading ? (
          <SkeletonRows />
        ) : shown.length === 0 ? (
          <div className="p-8 text-center text-slate-500">
            {sent.length === 0 ? 'لم يُرسل أي إشعار بعد.' : 'لا يوجد إشعار يطابق البحث.'}
          </div>
        ) : (
          <ul className="divide-y divide-slate-100">
            {shown.map((n) => {
              const share = n.students ? Math.round((n.read / n.students) * 100) : 0;
              const fromSupervisor = n.sender_role === 'supervisor';
              return (
                <li key={n.id} className="flex gap-4 p-4">
                  <div className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full ${
                    fromSupervisor ? 'bg-emerald-50 text-emerald-600' : 'bg-blue-50 text-blue-600'}`}>
                    {fromSupervisor ? <Bus className="h-5 w-5" /> : <Bell className="h-5 w-5" />}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-baseline justify-between gap-2">
                      <h3 className="font-bold text-slate-800">{n.title}</h3>
                      <span className="text-xs text-slate-400">{when(n.created_at)}</span>
                    </div>
                    <p className="mt-1 whitespace-pre-line text-sm text-slate-600">{n.body}</p>
                    <div className="mt-2 flex flex-wrap items-center gap-2 text-[11px] font-bold">
                      <span className={`rounded-full px-2 py-0.5 ${fromSupervisor ? 'bg-emerald-50 text-emerald-700' : 'bg-blue-50 text-blue-700'}`}>
                        {fromSupervisor ? `المشرف ${n.sender_name}` : `الإدارة · ${n.sender_name}`}
                      </span>
                      <span className="flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-slate-600">
                        <Users className="h-3 w-3" />{n.audience}
                      </span>
                    </div>
                    <div className="mt-2 flex items-center gap-2">
                      <div className="h-1.5 w-32 overflow-hidden rounded-full bg-slate-100">
                        <div className="h-full rounded-full bg-emerald-500" style={{ width: `${share}%` }} />
                      </div>
                      <span className="text-[11px] text-slate-500">قرأه {n.read} من {n.students} طالب</span>
                    </div>
                  </div>
                  <button onClick={() => void handleDelete(n)} title="حذف الإشعار"
                    className="self-start text-rose-400 transition hover:text-rose-600">
                    <Trash2 className="h-4 w-4" />
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
};
