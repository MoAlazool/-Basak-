import React from 'react';
import { Link } from 'react-router-dom';
import {
  Button, Dialog, Icon, InfoRows, Ltr, Money, Note, SidePanel, SkeletonText, StatePill, num, dayText, cairo, type StateKey,
} from '../../ui';
import { useCompanyOverview } from '../../lib/overview';
import { CompanyGovernoratesCard } from '../CompanyGovernoratesCard';
import { readiness, statusQuestion, useCompanyDetail, phoneGroups, type CompanyStatus, type PlatformCompany } from '../../lib/platform';

export const STATUS_STATE: Record<CompanyStatus, [StateKey, string]> = { active: ['on', 'تعمل'], suspended: ['suspended', 'موقوفة'], archived: ['archived', 'مؤرشفة'] };
export const CompanyState: React.FC<{ status: CompanyStatus }> = ({ status }) => <StatePill state={STATUS_STATE[status][0]} label={STATUS_STATE[status][1]} />;

const Tile: React.FC<{ label: string; value: React.ReactNode }> = ({ label, value }) => (
  <div className="flex min-w-0 flex-col rounded-control bg-ground px-3 py-2 sm:px-3.5">
    <span className="truncate text-cap text-ink-2">{label}</span>
    <span className="text-[20px] font-semibold leading-7 tabular">{value}</span>
  </div>
);

/**
 * One company in the side panel (AdmPlatCompaniesPanel, AdmPlatCompanyPhone): its
 * numbers, whether a student can subscribe and why not, who runs it, and the one
 * status change its state allows, each through a question.
 */
export const CompanyPanel: React.FC<{
  company: PlatformCompany | null; onClose: () => void; onStatus: (to: CompanyStatus) => void; busy: boolean; online: boolean;
}> = ({ company, onClose, onStatus, busy, online }) => {
  const c = company;
  const detail = useCompanyDetail(c?.id ?? null);
  const overview = useCompanyOverview(c?.id ?? '');
  const o = c ? overview.data : null;
  const d = detail.data;
  if (!c) return null;
  const working = c.status === 'active';
  const since = c.status_changed_at ?? d?.company.status_changed_at ?? null;
  const contact = d?.company ?? c;
  const enter = <Button key="enter" iconEnd="fwd" to={`/c/${c.id}`}>ادخل إلى الشركة</Button>;
  const footer = working ? (
    <>
      <Button kind="dangerQuiet" icon="power" disabled={busy || !online} onClick={() => onStatus('suspended')}>أوقف الشركة</Button>
      <span className="hidden flex-1 sm:block" />{enter}
    </>
  ) : (
    <>
      {c.status === 'suspended' && <Button kind="dangerQuiet" disabled={busy || !online} onClick={() => onStatus('archived')}>أرشف الشركة</Button>}
      <span className="hidden flex-1 sm:block" />
      <Button kind="secondary" to={`/c/${c.id}`}>ادخل</Button>
      <Button icon="power" disabled={busy || !online} onClick={() => onStatus('active')}>أعد تشغيل الشركة</Button>
    </>
  );
  const admins = d?.admins ?? [];
  const items = d ? readiness(d) : [];
  return (
    <SidePanel open onClose={onClose} title={c.name} sub="شركة نقل" meta={<CompanyState status={c.status} />} footer={footer} backLabel="الشركات">
      {working ? (
        <>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            <Tile label="الطلاب" value={num(o?.members ?? c.students)} />
            <Tile label="اشتراكات نشطة" value={o ? num(o.active_subscriptions) : '—'} />
            <Tile label="ركاب الغد" value={o ? num(o.riders_next) : '—'} />
            <Tile label="إيصالات تنتظر" value={o ? num(o.pending_receipts) : '—'} />
          </div>
          <section className="flex flex-col gap-3">
            <h3 className="m-0 text-card">هل يستطيع طالب أن يشترك؟</h3>
            {detail.loading ? <SkeletonText rows={6} /> : detail.error ? (
              <Note tone="danger" title="تعذّر تحميل حال الشركة" action={<Button kind="link" sm onClick={() => void detail.reload()}>إعادة المحاولة</Button>}>تأكد من اتصالك ثم حاول مرة أخرى.</Note>
            ) : (
              <ul className="m-0 flex list-none flex-col gap-3.5 p-0">
                {items.map((it) => (
                  <li key={it.key} className="flex items-start gap-3">
                    <span aria-hidden="true" className={`mt-0.5 flex h-6 w-6 flex-none items-center justify-center rounded-full ${it.ok ? 'bg-ok-bg text-ok' : 'bg-warn-bg text-warn'}`}>
                      <Icon name={it.ok ? 'check' : 'alert'} size={14} stroke={2.5} />
                    </span>
                    <span className="flex min-w-0 flex-col">
                      <span className="text-small font-semibold">{it.title}<span className="sr-only">{it.ok ? ' (جاهز)' : ' (ينقصه شيء)'}</span></span>
                      {it.sub && <span className="text-label text-ink-2">{it.sub}</span>}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </>
      ) : (
        <Note tone={c.status === 'suspended' ? 'warning' : 'neutral'} icon={c.status === 'suspended' ? 'alert' : 'info'}
          title={`${c.status === 'suspended' ? 'موقوفة' : 'مؤرشفة'}${since ? ` منذ ${dayText(cairo(since).day)}` : ''}`}>
          {c.status === 'suspended' ? 'مديروها ومشرفوها لا يدخلون، ولا يراها الطلاب. بياناتها كما هي.' : 'لا تظهر في القوائم ولا يراها الطلاب. بياناتها كما هي، ويمكن إعادة تشغيلها.'}
        </Note>
      )}
      <section className="flex flex-col gap-1">
        <h3 className="m-0 text-card">عن الشركة</h3>
        <InfoRows labelW={140} rows={working ? [
          ['أُنشئت', dayText(cairo(c.created_at).day)],
          ['رقم التواصل', contact.contact_phone ? <Ltr>{phoneGroups(contact.contact_phone)}</Ltr> : <span className="text-ink-3">لم يُكتب</span>],
          ['جهة التواصل', contact.contact_label || <span className="text-ink-3">لم تُكتب</span>],
          ['المديرون', (
            <span className="flex items-baseline justify-between gap-3">
              <span>{admins.length ? admins.map((a) => a.full_name).join(' · ') : detail.loading ? '…' : 'لا مدير بعد'}</span>
              <Link to={`/platform/admins?company=${c.id}`} className="text-label font-medium text-teal hover:underline">اعرضهم</Link>
            </span>
          )],
          ['الإيرادات المسجّلة', o ? <Money value={o.revenue} /> : '—'],
        ] : [
          ['أُنشئت', dayText(cairo(c.created_at).day)],
          ['الطلاب', num(c.students)],
          ['الخطوط', num(c.lines)],
          ['المديرون', num(c.admins)],
        ]} />
      </section>
      <section className="flex flex-col gap-2">
        <h3 className="m-0 text-card">المحافظات التي تخدمها</h3>
        <CompanyGovernoratesCard companyId={c.id} compact />
      </section>
    </SidePanel>
  );
};

/** The question before a status change: what happens to the company's admins, supervisors and students. */
export const StatusDialog: React.FC<{
  company: PlatformCompany | null; to: CompanyStatus | null; onClose: () => void; onConfirm: () => void; busy: boolean;
}> = ({ company, to, onClose, onConfirm, busy }) => {
  if (!company || !to) return null;
  const q = statusQuestion(to, company);
  const danger = to !== 'active';
  return (
    <Dialog open onClose={onClose} title={q.title} icon={to === 'archived' ? 'trash' : 'power'} tone={danger ? 'danger' : 'teal'}
      actions={[
        <Button key="back" kind="secondary" onClick={onClose}>رجوع</Button>,
        <Button key="go" kind={danger ? 'danger' : 'primary'} loading={busy} onClick={onConfirm}>{q.confirm}</Button>,
      ]}>
      {q.body.map((p) => <p key={p} className="m-0">{p}</p>)}
    </Dialog>
  );
};
