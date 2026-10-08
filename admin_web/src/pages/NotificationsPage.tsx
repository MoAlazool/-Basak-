import React, { useState } from 'react';
import { Info } from 'lucide-react';
import { useCompany } from '../lib/adminScope';
import type { StatusFilter } from '../lib/notifications';
import { useNotificationHistory } from '../lib/notificationsData';
import { Composer } from '../components/notifications/Composer';
import { History } from '../components/notifications/History';

/**
 * Notifications to the company's students: written here (the whole company, a
 * line, a trip or a university; now or at a set time), sent by supervisors from
 * the app, or sent by the system itself. Everything appears below with what is
 * actually known about it: who received it, who read it, and what the push
 * provider accepted.
 */
export const NotificationsPage: React.FC = () => {
  const companyId = useCompany().id;
  const [filter, setFilter] = useState<StatusFilter>('all');
  // One query feeds the list and tells whether push is connected.
  const history = useNotificationHistory(companyId, filter);

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-slate-800">الإشعارات</h1>
        <p className="text-sm text-slate-500">
          أرسل إشعاراً لكل طلاب الشركة أو لخط أو رحلة أو جامعة، الآن أو في موعد تحدده. يرسل المشرفون أيضاً من التطبيق، ويظهر كل ما أُرسل هنا.
        </p>
      </div>

      {history.pushConfigured === false && (
        <div role="status" className="flex items-start gap-3 rounded-2xl border border-sky-100 bg-sky-50 p-4 text-sm text-sky-800">
          <Info className="mt-0.5 h-4 w-4 shrink-0" />
          <p>
            <b>الإشعارات الفورية على الهاتف غير مربوطة بعد.</b>{' '}
            الإشعارات التي ترسلها تصل إلى الطلاب داخل التطبيق في صفحة الإشعارات، ولن تظهر كتنبيه على الهاتف حتى يكتمل الربط.
          </p>
        </div>
      )}

      <Composer companyId={companyId} />
      <History companyId={companyId} filter={filter} onFilter={setFilter} history={history} />
    </div>
  );
};
