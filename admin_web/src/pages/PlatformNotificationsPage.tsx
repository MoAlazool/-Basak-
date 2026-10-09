import React, { useState } from 'react';
import { Smartphone } from 'lucide-react';
import { Topbar } from '../components/Topbar';
import { Skeleton } from '../components/Skeleton';
import { count } from '../components/StatsRow';
import type { PlatformPush, StatusFilter } from '../lib/notifications';
import { usePlatformNotificationActions, usePlatformNotificationHistory } from '../lib/notificationsData';
import { usePlatformCompanies } from '../lib/reference';
import { PlatformComposer } from '../components/notifications/PlatformComposer';
import { History } from '../components/notifications/History';

const CONNECTION = {
  yes: { label: 'مربوطة', className: 'bg-emerald-50 text-emerald-700' },
  no: { label: 'غير مربوطة', className: 'bg-amber-50 text-amber-700' },
  unknown: { label: 'غير معروفة', className: 'bg-slate-100 text-slate-500' },
};

/**
 * Push across the platform, in numbers that only say what was measured: the
 * provider accepting a message is not the phone showing it.
 */
const PushStatus: React.FC<{ push: PlatformPush | null; loading: boolean }> = ({ push, loading }) => {
  const connection = CONNECTION[push?.configured === true ? 'yes' : push?.configured === false ? 'no' : 'unknown'];
  const tiles: { label: string; value: number | undefined; hint?: string; tone?: string }[] = [
    { label: 'أجهزة مسجّلة', value: push?.devices, hint: push ? `iOS ${count(push.ios ?? 0)} · Android ${count(push.android ?? 0)}` : undefined },
    { label: 'في الانتظار الآن', value: push?.queued },
    { label: 'قبِلها مزوّد الإشعارات', value: push?.accepted_24h, hint: 'آخر 24 ساعة' },
    { label: 'فشلت', value: push?.failed_24h, hint: 'آخر 24 ساعة', tone: (push?.failed_24h ?? 0) > 0 ? 'text-rose-700' : undefined },
  ];
  return (
    <div className="rounded-2xl border border-slate-100 bg-white p-5 shadow-sm">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="flex items-center gap-2 text-base font-bold text-slate-700">
          <Smartphone className="h-4 w-4 text-blue-600" />
          الإشعارات الفورية (Push)
        </h2>
        {loading ? <Skeleton className="h-5 w-20" />
          : <span className={`rounded-full px-2.5 py-0.5 text-[11px] font-bold ${connection.className}`}>{connection.label}</span>}
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2 lg:grid-cols-4">
        {tiles.map((tile) => (
          <div key={tile.label} className="rounded-xl bg-slate-50 p-3">
            {loading ? <Skeleton className="h-6 w-12" />
              : <p className={`text-lg font-extrabold ${tile.tone ?? 'text-slate-800'}`}>{tile.value === undefined ? '—' : count(tile.value ?? 0)}</p>}
            <p className="mt-0.5 text-[11px] leading-4 text-slate-500">{tile.label}</p>
            {tile.hint && <p className="text-[11px] leading-4 text-slate-400" dir="auto">{tile.hint}</p>}
          </div>
        ))}
      </div>
      <p className="mt-2 text-[11px] leading-5 text-slate-400">
        {push?.configured === false && 'الربط غير مكتمل: الإشعارات تصل داخل التطبيق فقط ولا تظهر كتنبيه على الهاتف. '}
        «قبِلها مزوّد الإشعارات» تعني أن مزوّد الخدمة استلم الرسالة ليوصلها، ولا تعني أنها ظهرت على الهاتف.
      </p>
    </div>
  );
};

/**
 * The platform admin's notifications: the state of push for everyone, a message
 * to the students of every company (or of chosen ones), and what every company
 * sent, with what is actually known about each.
 */
export const PlatformNotificationsPage: React.FC = () => {
  const [filter, setFilter] = useState<StatusFilter>('all');
  const [companyId, setCompanyId] = useState('');
  // One query feeds the list and the push numbers.
  const history = usePlatformNotificationHistory(filter, companyId);
  const actions = usePlatformNotificationActions();
  const companies = usePlatformCompanies().data ?? [];

  return (
    <div className="space-y-6">
      <Topbar title="إشعارات المنصة" subtitle="أرسل لطلاب كل الشركات، وتابع ما أرسلته كل شركة" />

      <PushStatus push={history.push} loading={history.loading} />
      <PlatformComposer />
      <History filter={filter} onFilter={setFilter} history={history} actions={actions}
        filters={(
          <select value={companyId} onChange={(e) => setCompanyId(e.target.value)} aria-label="الشركة"
            className="rounded-full border border-slate-200 bg-white px-3 py-1 text-xs font-bold text-slate-600 focus:border-blue-500 focus:outline-none">
            <option value="">كل الشركات</option>
            {companies.map((company) => <option key={company.id} value={company.id}>{company.name}</option>)}
          </select>
        )} />
    </div>
  );
};
