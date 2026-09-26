import React, { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { MapPin, Plus, Clock } from 'lucide-react';

interface Line {
  id: string;
  name: string;
  company_id: string;
  price_termly: number;
  price_yearly: number;
  price_daily: number;
  is_active: boolean;
  companies?: { name: string };
  stations?: Station[];
}

interface Station {
  id: string;
  line_id: string;
  name: string;
  order_index: number;
  departure_time: string;
  return_time: string;
}

export const LinesPage: React.FC = () => {
  const [lines, setLines] = useState<Line[]>([]);
  const [companies, setCompanies] = useState<{ id: string; name: string }[]>([]);
  const [loading, setLoading] = useState(true);

  // Form states
  const [selectedCompanyId, setSelectedCompanyId] = useState('');
  const [lineName, setLineName] = useState('');
  const [priceTermly, setPriceTermly] = useState('3500');
  const [priceYearly, setPriceYearly] = useState('6500');
  const [priceDaily, setPriceDaily] = useState('50');

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      // Fetch lines with company and stations
      const { data: linesData, error: lError } = await supabase
        .from('lines')
        .select(`
          *,
          companies(name),
          stations(id, name, order_index, departure_time, return_time)
        `)
        .order('name');
      if (lError) throw lError;
      setLines(linesData || []);

      // Fetch active companies
      const { data: compData, error: cError } = await supabase
        .from('companies')
        .select('id, name')
        .eq('is_active', true);
      if (cError) throw cError;
      setCompanies(compData || []);
      if (compData && compData.length > 0) {
        setSelectedCompanyId(compData[0].id);
      }
    } catch (err) {
      console.error('Error fetching lines data:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateLine = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!lineName.trim() || !selectedCompanyId) return;

    try {
      const { error } = await supabase.from('lines').insert({
        company_id: selectedCompanyId,
        name: lineName.trim(),
        price_termly: parseFloat(priceTermly),
        price_yearly: parseFloat(priceYearly),
        price_daily: parseFloat(priceDaily),
        is_active: true,
      });

      if (error) throw error;
      setLineName('');
      fetchData();
    } catch (err: any) {
      alert('فشل إضافة الخط: ' + err.message);
    }
  };

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">إدارة خطوط السير والمحطات</h1>
        <p className="text-sm text-slate-500">
          إضافة خطوط السير، تسعير الاشتراكات (ترم، سنوي، يومي كاش)، ومحطات التوقف
        </p>
      </div>

      {/* Add Line Form */}
      <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
        <h2 className="text-base font-bold text-slate-700">إضافة خط باص جديد</h2>
        <form onSubmit={handleCreateLine} className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-6">
          <div className="lg:col-span-2">
            <label className="text-xs font-semibold text-slate-500">اسم الخط</label>
            <input
              type="text"
              placeholder="مثال: خط مدينة نصر - الجامعة"
              value={lineName}
              onChange={(e) => setLineName(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">الشركة المشغلة</label>
            <select
              value={selectedCompanyId}
              onChange={(e) => setSelectedCompanyId(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            >
              {companies.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">سعر الترم (ج.م)</label>
            <input
              type="number"
              value={priceTermly}
              onChange={(e) => setPriceTermly(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">سعر السنوي (ج.م)</label>
            <input
              type="number"
              value={priceYearly}
              onChange={(e) => setPriceYearly(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div>
            <label className="text-xs font-semibold text-slate-500">سعر اليومي كاش (ج.م)</label>
            <input
              type="number"
              value={priceDaily}
              onChange={(e) => setPriceDaily(e.target.value)}
              className="mt-1 w-full rounded-xl border border-slate-200 px-3.5 py-2 text-sm focus:border-blue-500 focus:outline-none"
              required
            />
          </div>

          <div className="sm:col-span-2 lg:col-span-6 flex justify-end">
            <button
              type="submit"
              className="flex items-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700"
            >
              <Plus className="h-4 w-4" />
              حفظ الخط الجديد
            </button>
          </div>
        </form>
      </div>

      {/* Lines & Stations List */}
      <div className="space-y-4">
        {loading ? (
          <div className="flex h-40 items-center justify-center">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-blue-500 border-t-transparent" />
          </div>
        ) : (
          lines.map((line) => (
            <div
              key={line.id}
              className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm"
            >
              <div className="flex flex-wrap items-center justify-between gap-4 border-b border-slate-100 pb-4">
                <div>
                  <h3 className="text-lg font-bold text-slate-800">{line.name}</h3>
                  <p className="text-xs text-slate-500">
                    الشركة: {line.companies?.name || 'غير محدد'}
                  </p>
                </div>
                <div className="flex items-center gap-3">
                  <span className="rounded-lg bg-blue-50 px-3 py-1 text-xs font-bold text-blue-700">
                    الترم: {line.price_termly} ج.م
                  </span>
                  <span className="rounded-lg bg-teal-50 px-3 py-1 text-xs font-bold text-teal-700">
                    سنوي: {line.price_yearly} ج.م
                  </span>
                  <span className="rounded-lg bg-amber-50 px-3 py-1 text-xs font-bold text-amber-700">
                    يومي: {line.price_daily} ج.م
                  </span>
                </div>
              </div>

              {/* Stations List for this Line */}
              <div className="mt-4">
                <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400">
                  محطات الركوب والتوقيتات
                </h4>
                {line.stations && line.stations.length > 0 ? (
                  <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
                    {line.stations
                      .sort((a, b) => a.order_index - b.order_index)
                      .map((st) => (
                        <div
                          key={st.id}
                          className="flex items-center justify-between rounded-xl border border-slate-100 bg-slate-50/50 p-3 text-xs"
                        >
                          <div className="flex items-center gap-2">
                            <MapPin className="h-4 w-4 text-blue-500" />
                            <span className="font-semibold text-slate-700">{st.name}</span>
                          </div>
                          <div className="flex items-center gap-2 text-slate-500">
                            <Clock className="h-3 w-3" />
                            <span>ذهاب {st.departure_time}</span>
                          </div>
                        </div>
                      ))}
                  </div>
                ) : (
                  <p className="mt-2 text-xs text-slate-400">لا توجد محطات مسجلة لهذا الخط حتى الآن.</p>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
