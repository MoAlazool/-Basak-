import React, { useEffect, useMemo, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAdminScope } from '../lib/adminScope';
import { invokeEdgeFunction } from '../lib/edgeFunctions';
import { UserCheck, Plus, CheckCircle, XCircle, Trash2, Bus, Pencil, Save, X } from 'lucide-react';

interface Supervisor {
  id: string;
  phone: string;
  full_name: string;
  company_id: string;
  is_active: boolean;
  created_at: string;
  companies?: { name: string } | null;
}

interface LineOption { id: string; name: string; company_id: string; is_active: boolean; }

/** Checkbox list of a company's lines. */
const LinePicker: React.FC<{
  lines: LineOption[];
  selected: string[];
  onChange: (ids: string[]) => void;
}> = ({ lines, selected, onChange }) => {
  if (lines.length === 0) {
    return <p className="text-xs text-amber-700">لا توجد خطوط لهذه الشركة بعد. أضف خطاً من صفحة الخطوط أولاً.</p>;
  }
  const toggle = (id: string) =>
    onChange(selected.includes(id) ? selected.filter((x) => x !== id) : [...selected, id]);
  return (
    <div className="flex flex-wrap gap-2">
      {lines.map((line) => {
        const on = selected.includes(line.id);
        return (
          <label key={line.id}
            className={`flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-1.5 text-xs font-semibold transition ${
              on ? 'border-blue-500 bg-blue-50 text-blue-700' : 'border-slate-200 bg-white text-slate-600 hover:border-blue-300'}`}>
            <input type="checkbox" className="accent-blue-600" checked={on} onChange={() => toggle(line.id)} />
            <Bus className="h-3.5 w-3.5" />
            {line.name}{!line.is_active && ' (موقوف)'}
          </label>
        );
      })}
    </div>
  );
};

export const SupervisorsPage: React.FC = () => {
  const admin = useAdminScope();
  const [supervisors, setSupervisors] = useState<Supervisor[]>([]);
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const [lines, setLines] = useState<LineOption[]>([]);
  const [assignments, setAssignments] = useState<Record<string, string[]>>({});
  const [loading, setLoading] = useState(true);
  const [pageError, setPageError] = useState('');

  // New supervisor form
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [companyId, setCompanyId] = useState('');
  const [lineIds, setLineIds] = useState<string[]>([]);
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Editing the lines of an existing supervisor
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingLines, setEditingLines] = useState<string[]>([]);
  const [savingLines, setSavingLines] = useState(false);

  useEffect(() => {
    void fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      setPageError('');
      const [supRes, lineRes, assignRes] = await Promise.all([
        supabase.from('supervisors')
          .select('id, phone, full_name, company_id, is_active, created_at, companies(name)')
          .order('created_at', { ascending: false }),
        supabase.from('lines').select('id, name, company_id, is_active').order('name'),
        supabase.from('supervisor_lines').select('supervisor_id, line_id'),
      ]);
      if (supRes.error) throw supRes.error;
      if (lineRes.error) throw lineRes.error;
      if (assignRes.error) throw assignRes.error;
      setSupervisors((supRes.data || []) as unknown as Supervisor[]);
      setLines((lineRes.data || []) as LineOption[]);
      const map: Record<string, string[]> = {};
      (assignRes.data || []).forEach((row) => {
        (map[row.supervisor_id] ||= []).push(row.line_id);
      });
      setAssignments(map);

      if (admin.role === 'company_admin' && admin.company_id) {
        setCompanies([{ id: admin.company_id, name: admin.companyName || '' }]);
        setCompanyId(admin.company_id);
      } else {
        const { data: compData, error: cError } = await supabase
          .from('companies').select('id, name').eq('is_active', true).order('name');
        if (cError) throw cError;
        setCompanies(compData || []);
        setCompanyId((current) => current || compData?.[0]?.id || '');
      }
    } catch (err) {
      console.error('Error fetching supervisors:', err);
      setPageError(err instanceof Error ? err.message : 'تعذر تحميل المشرفين.');
    } finally {
      setLoading(false);
    }
  };

  const linesById = useMemo(() => new Map(lines.map((line) => [line.id, line])), [lines]);
  const companyLines = (id: string) => lines.filter((line) => line.company_id === id);

  const handleAddSupervisor = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!fullName.trim() || !phone.trim() || !companyId) {
      alert('يرجى ملء جميع الحقول المطلوبة.');
      return;
    }
    if (password.trim().length < 8) {
      alert('كلمة المرور يجب ألا تقل عن 8 أحرف.');
      return;
    }
    if (lineIds.length === 0) {
      alert('اختر خطاً واحداً على الأقل يكون المشرف مسؤولاً عنه.');
      return;
    }

    try {
      setIsSubmitting(true);
      // Server-side creation: confirmed Auth account, company-scoped row and the
      // supervisor's lines, all-or-nothing. No password is stored by Basak.
      await invokeEdgeFunction('admin-create-supervisor', {
        fullName: fullName.trim(),
        phone: phone.trim(),
        password: password.trim(),
        companyId,
        lineIds,
      });
      setFullName('');
      setPhone('');
      setPassword('');
      setLineIds([]);
      await fetchData();
      alert('تمت إضافة المشرف وتعيين خطوطه. سلّمه رقم الهاتف وكلمة المرور لتسجيل الدخول في التطبيق (لا تُحفظ كلمة المرور في النظام).');
    } catch (err: any) {
      alert('فشل إضافة المشرف: ' + err.message);
    } finally {
      setIsSubmitting(false);
    }
  };

  const saveLines = async (supervisor: Supervisor) => {
    try {
      setSavingLines(true);
      const { error } = await supabase.rpc('set_supervisor_lines', {
        p_supervisor_id: supervisor.id,
        p_line_ids: editingLines,
      });
      if (error) throw error;
      setEditingId(null);
      await fetchData();
    } catch (err: any) {
      alert('فشل حفظ خطوط المشرف: ' + err.message);
    } finally {
      setSavingLines(false);
    }
  };

  const handleToggleActive = async (sup: Supervisor) => {
    const { error } = await supabase
      .from('supervisors')
      .update({ is_active: !sup.is_active })
      .eq('id', sup.id);
    if (error) alert('فشل تغيير الحالة: ' + error.message);
    else void fetchData();
  };

  const handleDelete = async (id: string, name: string) => {
    if (!confirm(`هل أنت متأكد من حذف المشرف "${name}"؟ سيتم حذف حساب الدخول الخاص به أيضاً.`)) return;
    try {
      await invokeEdgeFunction('admin-delete-supervisor', { supervisorId: id });
      void fetchData();
    } catch (err: any) {
      alert('فشل الحذف: ' + err.message);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة المشرفين</h1>
        <p className="text-sm text-slate-500">
          الشركة ← الخط ← المشرف. يرى المشرف في التطبيق الخطوط المسندة إليه فقط. كلمة المرور تُسلَّم للمشرف ولا تُحفظ في النظام
        </p>
      </div>

      {pageError && (
        <div role="alert" className="rounded-xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700">
          تعذر تحميل البيانات: {pageError}
          <button className="mr-3 font-bold underline" onClick={() => void fetchData()}>إعادة المحاولة</button>
        </div>
      )}

      {/* Add Supervisor Card */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">تعيين مشرف جديد</h2>
        <form onSubmit={handleAddSupervisor} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div>
            <label className="text-xs font-semibold text-slate-500">اسم المشرف</label>
            <input type="text" placeholder="مثال: أحمد محمود" value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">رقم الهاتف (الفريد للدخول)</label>
            <input type="tel" placeholder="01xxxxxxxxx" value={phone} onChange={(e) => setPhone(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">كلمة المرور لتطبيق الهاتف</label>
            <input type="text" autoComplete="new-password" minLength={8} placeholder="8 أحرف على الأقل" value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required />
          </div>

          {admin.role === 'super_admin' && <div>
            <label className="text-xs font-semibold text-slate-500">الشركة التابع لها</label>
            <select value={companyId}
              onChange={(e) => { setCompanyId(e.target.value); setLineIds([]); }}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none" required>
              {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </div>}

          <div className="sm:col-span-2 lg:col-span-4">
            <label className="text-xs font-semibold text-slate-500">الخطوط المسؤول عنها (يمكن اختيار أكثر من خط)</label>
            <div className="mt-2">
              <LinePicker lines={companyLines(companyId)} selected={lineIds} onChange={setLineIds} />
            </div>
          </div>

          <div className="sm:col-span-2 lg:col-span-4 flex justify-end">
            <button type="submit" disabled={isSubmitting || lineIds.length === 0}
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50">
              <Plus className="h-4 w-4" />
              {isSubmitting ? 'جاري الإضافة...' : 'إضافة المشرف'}
            </button>
          </div>
        </form>
      </div>

      {/* Supervisors Table */}
      <div className="rounded-2xl border border-slate-100 bg-white shadow-sm overflow-x-auto">
        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : supervisors.length === 0 ? (
          <div className="p-8 text-center text-slate-500">لا يوجد مشرفون مسجلون حالياً.</div>
        ) : (
          <table className="w-full min-w-[760px] text-right text-sm">
            <thead className="border-b border-slate-100 bg-slate-50/50 text-slate-500">
              <tr>
                <th className="p-4 font-bold">اسم المشرف</th>
                <th className="p-4 font-bold">رقم الهاتف</th>
                <th className="p-4 font-bold">الشركة</th>
                <th className="p-4 font-bold">الخطوط المسندة</th>
                <th className="p-4 font-bold">الحالة</th>
                <th className="p-4 font-bold">إجراءات</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {supervisors.map((s) => {
                const assigned = assignments[s.id] || [];
                const editing = editingId === s.id;
                return (
                  <tr key={s.id} className="align-top hover:bg-slate-50/80">
                    <td className="p-4 font-semibold text-slate-800">
                      <div className="flex items-center gap-3">
                        <UserCheck className="h-5 w-5 text-slate-400" />
                        {s.full_name}
                      </div>
                    </td>
                    <td className="p-4 text-slate-600 font-mono text-xs">{s.phone}</td>
                    <td className="p-4 text-slate-600">{s.companies?.name || '-'}</td>
                    <td className="p-4">
                      {editing ? (
                        <div className="space-y-2">
                          <LinePicker lines={companyLines(s.company_id)} selected={editingLines} onChange={setEditingLines} />
                          {editingLines.length === 0 && (
                            <p className="text-[11px] text-amber-700">بدون خطوط لن يرى المشرف أي خط في التطبيق.</p>
                          )}
                          <div className="flex gap-2">
                            <button disabled={savingLines} onClick={() => void saveLines(s)}
                              className="flex items-center gap-1 rounded-lg bg-blue-600 px-3 py-1 text-xs font-bold text-white disabled:opacity-50">
                              <Save className="h-3.5 w-3.5" />حفظ
                            </button>
                            <button onClick={() => setEditingId(null)}
                              className="flex items-center gap-1 rounded-lg border border-slate-200 px-3 py-1 text-xs text-slate-600">
                              <X className="h-3.5 w-3.5" />إلغاء
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="flex flex-wrap items-center gap-1.5">
                          {assigned.length === 0
                            ? <span className="rounded-full bg-amber-50 px-2 py-0.5 text-[11px] font-bold text-amber-700">بدون خطوط</span>
                            : assigned.map((id) => (
                              <span key={id} className="rounded-full bg-sky-50 px-2 py-0.5 text-[11px] font-bold text-sky-700">
                                {linesById.get(id)?.name || 'خط'}
                              </span>
                            ))}
                          <button title="تعديل الخطوط" onClick={() => { setEditingId(s.id); setEditingLines(assigned); }}
                            className="text-slate-400 hover:text-blue-600">
                            <Pencil className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      )}
                    </td>
                    <td className="p-4">
                      <button onClick={() => void handleToggleActive(s)}
                        className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold transition hover:opacity-80 ${
                          s.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-700'}`}>
                        {s.is_active ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
                        {s.is_active ? 'نشط' : 'معطل'}
                      </button>
                    </td>
                    <td className="p-4">
                      <button onClick={() => void handleDelete(s.id, s.full_name)}
                        className="text-rose-400 hover:text-rose-600 transition" title="حذف المشرف">
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
};
