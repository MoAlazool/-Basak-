import React, { useMemo } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import {
  Badge, Button, Card, EmptyState, ErrorState, Ltr, Money, Note, Page, PageHeader, PhoneBar, Pill, SectionHead,
  SkeletonStat, SkeletonTable, StatCard, StatePill, dayText, phoneText,
} from '../ui';
import { useCompany } from '../lib/adminScope';
import { useLines, useSupervisorLines, useSupervisors, useUniversities, type LineRow } from '../lib/reference';
import { statsFor, useLinesStats, useSaleContext, type LineStats } from '../lib/linesData';
import { countOf, joinAnd, lineVisibility, unitWord, W, type StepNo } from '../lib/lines';
import { SALE_OPTIONS, optionName } from '../lib/saleOptions';
import { LineMenu, useLineActions, type MenuItem, type MenuTrigger } from '../components/lines/LineActions';
import { DepartureTable, PhoneTrips, ReturnList } from '../components/lines/LineTimetable';
import { LineWizard } from '../components/lines/LineWizard';

const n = (v: number) => v.toLocaleString('en-US');

/** What «تعديل الخط» opens: each part of the line straight at its own step of the editor. */
const EDIT_PARTS: { step: StepNo; label: string; icon: MenuItem['icon'] }[] = [
  { step: 1, label: 'الاسم والجامعات والمقاعد', icon: 'school' },
  { step: 2, label: 'المحطات', icon: 'pin' },
  { step: 3, label: 'المواعيد والرحلات', icon: 'clock' },
  { step: 4, label: 'الأسعار', icon: 'card' },
];
const EditMenu: React.FC<{ to: (s: StepNo) => string; go: (to: string) => void; trigger: MenuTrigger; sm?: boolean }> = ({ to, go, trigger, sm = false }) => (
  <LineMenu label="تعديل الخط" sm={sm} trigger={trigger} items={EDIT_PARTS.map((p) => ({ label: p.label, icon: p.icon, onClick: () => go(to(p.step)) }))} />
);
/** A quiet «✎ تعديل …» link beside a section's title. */
const EditLink: React.FC<{ to: string; disabled?: boolean; children: React.ReactNode }> = ({ to, disabled, children }) => (
  <Button kind="link" sm icon="pencil" to={to} disabled={disabled}>{children}</Button>
);

/** A line's own page: who rides it tomorrow, its timetable, prices and supervisors (docs/canvas/AdmLine*). */
export const LinePage: React.FC = () => {
  const { lineId = '' } = useParams();
  const [params] = useSearchParams();
  const company = useCompany();
  const lines = useLines(company.id);
  const line = lines.data?.find((l) => l.id === lineId);
  const edit = params.get('edit');
  if (lines.loading) return <LineSkeleton />;
  if (!line) {
    if (lines.error) return <Page><PageHeader title="الخط" back={{ label: 'الخطوط', to: `/c/${company.id}/lines` }} /><ErrorState card title="تعذّر تحميل الخط" text="لم نستطع جلب بيانات الخط. تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => void lines.reload()} /></Page>;
    return (
      <Page>
        <PageHeader title="الخط" back={{ label: 'الخطوط', to: `/c/${company.id}/lines` }} />
        <EmptyState card icon="route" title="هذا الخط غير موجود" text="ربما حُذف، أو أن الرابط قديم." action={<Button kind="secondary" to={`/c/${company.id}/lines`}>كل الخطوط</Button>} />
      </Page>
    );
  }
  if (edit) return <LineWizard key={line.id} mode="edit" line={line} startStep={(Math.min(5, Math.max(1, Number(edit) || 1)) as StepNo)} />;
  return <LineView line={line} />;
};

const LineSkeleton: React.FC = () => (
  <Page>
    <div className="flex flex-col gap-2"><span className="skeleton block h-4 w-20 rounded" /><span className="skeleton block h-8 w-56 rounded-lg" /><span className="skeleton block h-4 w-72 rounded" /></div>
    <div className="grid grid-cols-2 gap-3 sm:gap-6 lg:grid-cols-4"><SkeletonStat /><SkeletonStat /><SkeletonStat /><SkeletonStat /></div>
    <SkeletonTable rows={8} cols={6} />
  </Page>
);

const LineView: React.FC<{ line: LineRow }> = ({ line }) => {
  const company = useCompany();
  const navigate = useNavigate();
  const statsQ = useLinesStats(company.id);
  const stats = statsFor(statsQ.data, line.id);
  const universities = useUniversities().data;
  const supervisors = useSupervisors(company.id).data;
  const assignments = useSupervisorLines(company.id).data;
  const sale = useSaleContext(company.id);
  const uniName = useMemo(() => { const m = new Map((universities ?? []).map((u) => [u.id, u.name])); return (id: string) => m.get(id) ?? 'جامعة'; }, [universities]);
  const base = `/c/${company.id}/lines`;
  const actions = useLineActions(company.id, (id) => statsFor(statsQ.data, id), uniName, () => navigate(base));
  const vis = lineVisibility(line, { daily: sale.daily, uniName });
  const unis = line.line_universities.map((u) => uniName(u.university_id));
  const stations = line.stations.filter((s) => s.is_active).sort((a, b) => a.order_index - b.order_index);
  const going = line.line_trips.filter((t) => t.direction === 'departure' && t.is_active).sort((a, b) => a.start_time.localeCompare(b.start_time));
  const back = line.line_trips.filter((t) => t.direction === 'return' && t.is_active).sort((a, b) => a.start_time.localeCompare(b.start_time));
  const sups = (assignments ?? []).filter((a) => a.line_id === line.id).map((a) => (supervisors ?? []).find((s) => s.id === a.supervisor_id)).filter(Boolean)
    .map((s) => s!).sort((a, b) => Number(b.is_active) - Number(a.is_active));
  const editTo = (step?: StepNo) => `${base}/${line.id}?edit=${step ?? 1}`;
  const off = !line.is_active;
  const pill = vis.state === 'on' ? <Pill tone="success">يظهر للطلاب</Pill> : off ? <StatePill state="off" /> : <Pill tone="warning">لا يظهر للطلاب</Pill>;
  const rideDay = statsQ.data?.ride_date ? dayText(statsQ.data.ride_date, { weekday: true, year: false }) : null;
  const voteState = statsQ.data?.vote_open == null ? '' : statsQ.data.vote_open ? ' · التأكيد مفتوح، والأعداد تتغيّر' : ' · التأكيد مُقفل، والأعداد نهائية';

  return (
    <Page>
      <PageHeader title={`خط ${line.name}`} back={{ label: 'الخطوط', to: base }}
        meta={<>{pill}<span className="text-label text-ink-2 sm:hidden">{unis.join(' · ')}</span></>}
        sub={unis.length ? <span className="hidden sm:inline">يخدم {joinAnd(unis)}</span> : undefined}
        phoneActions={false}
        actions={<>
          <LineMenu label="إجراءات أخرى" sm={false} items={[
            { label: 'عيّن مشرفاً', sub: 'من صفحة المشرفون', icon: 'scan', onClick: () => navigate(`/c/${company.id}/supervisors`) },
            { label: 'حذف الخط', icon: 'trash', danger: true, sep: true, onClick: () => actions.ask('delete', line), disabled: !actions.online },
          ]} />
          {off ? <>
            <EditMenu to={editTo} go={navigate} trigger={{ text: 'تعديل الخط', icon: 'pencil', kind: 'outline', disabled: !actions.online }} />
            <Button icon="power" onClick={() => actions.ask('start', line)} disabled={!actions.online}>تشغيل الخط</Button>
          </> : <>
            <Button kind="outline" icon="power" onClick={() => actions.ask('stop', line)} disabled={!actions.online}>إيقاف الخط</Button>
            <EditMenu to={editTo} go={navigate} trigger={{ text: 'تعديل الخط', icon: 'pencil', disabled: !actions.online }} />
          </>}
        </>} />

      {off && (
        <Note tone="warning" title="الخط متوقف: لا يظهر للطلاب في التطبيق ولا يشترك فيه أحد جديد"
          action={<Button kind="outline" sm onClick={() => actions.ask('start', line)} disabled={!actions.online}>تشغيل الخط</Button>}>
          {stats.subscribers ? `مشتركوه الحاليون (${n(stats.subscribers)} ${unitWord(stats.subscribers, W.student)}) اشتراكهم كما هو ويؤكدون الركوب كالمعتاد. ` : ''}لا يمكن إسناده لمشرف جديد حتى تشغّله.
        </Note>
      )}
      {vis.state === 'hidden' && (
        <Note tone="warning" title={`لا يظهر للطلاب: ${vis.reason}`}
          action={<Button kind="outline" sm to={editTo(vis.step)} disabled={!actions.online}>{vis.fix}</Button>}>
          الخط يعمل، لكن الطلاب لا يجدونه في التطبيق حتى يكتمل.
        </Note>
      )}

      <Stats stats={stats} going={going.length} back={back.length} editTo={editTo(1)} online={actions.online} />

      {/* Desktop and tablet */}
      <section className="hidden flex-col gap-3 sm:flex">
        <SectionHead title="رحلات الذهاب" meta={rideDay ? <Badge tone="teal">ركاب {rideDay}</Badge> : undefined}
          end={<>
            <span className="text-label text-ink-2">{countOf(stations.length, W.station)} · {countOf(going.length, W.trip)}{voteState}</span>
            <span className="flex items-center gap-2">
              <EditLink to={editTo(2)} disabled={!actions.online}>تعديل المحطات</EditLink>
              <EditLink to={editTo(3)} disabled={!actions.online}>تعديل المواعيد</EditLink>
            </span>
          </>} />
        {going.length ? <DepartureTable stations={stations} trips={going} stats={stats} uniName={uniName} />
          : <EmptyState card icon="bus" title="لا رحلات ذهاب" text="أضف رحلة ذهاب بمواعيدها على المحطات، فالطلاب يختارون منها." action={<Button to={editTo(3)} icon="plus">أضف رحلة</Button>} />}
      </section>
      <div className="hidden grid-cols-1 gap-6 sm:grid lg:grid-cols-[minmax(0,1fr)_452px]">
        <section className="flex flex-col gap-3">
          <SectionHead title="العودة من الجامعة" end={<>
            <span className="text-label text-ink-2">يتحرك الباص من الجامعة ويعيد كل طالب إلى محطته</span>
            <EditLink to={editTo(3)} disabled={!actions.online}>تعديل المواعيد</EditLink>
          </>} />
          <ReturnList trips={back} stats={stats} uniName={uniName} />
        </section>
        <div className="flex flex-col gap-6 lg:pt-[48px]">
          <PricesCard line={line} sold={sale.sold} daily={sale.daily} companyId={company.id} editTo={editTo(4)} online={actions.online} />
          <SupervisorsCard sups={sups} companyId={company.id} />
        </div>
      </div>

      {/* Phone */}
      <section className="flex flex-col gap-3 sm:hidden">
        <SectionHead title="الرحلات" meta={rideDay ? <Badge tone="teal">ركاب {rideDay}</Badge> : undefined} />
        <PhoneTrips stations={stations} going={going} back={back} stats={stats} uniName={uniName} />
        <div className="flex flex-wrap items-center gap-x-4">
          <EditLink to={editTo(2)} disabled={!actions.online}>تعديل المحطات</EditLink>
          <EditLink to={editTo(3)} disabled={!actions.online}>تعديل المواعيد</EditLink>
        </div>
      </section>
      <div className="flex flex-col gap-5 sm:hidden">
        <PricesCard line={line} sold={sale.sold} daily={sale.daily} companyId={company.id} editTo={editTo(4)} online={actions.online} />
        <SupervisorsCard sups={sups} companyId={company.id} />
        <div className="flex flex-col gap-2">
          {off ? <Button kind="outline" full icon="power" onClick={() => actions.ask('start', line)} disabled={!actions.online}>تشغيل الخط</Button>
            : <Button kind="outline" full icon="power" onClick={() => actions.ask('stop', line)} disabled={!actions.online}>إيقاف الخط</Button>}
          <Button kind="link" full className="!text-bad" onClick={() => actions.ask('delete', line)} disabled={!actions.online}>حذف الخط</Button>
        </div>
      </div>
      <PhoneBar><EditMenu to={editTo} go={navigate} trigger={{ text: 'تعديل الخط', icon: 'pencil', full: true, disabled: !actions.online }} /></PhoneBar>
      {actions.dialogs}
    </Page>
  );
};

const Stats: React.FC<{ stats: LineStats; going: number; back: number; editTo: string; online: boolean }> = ({ stats, going, back, editTo, online }) => {
  const v = (x: number | null) => (x == null ? '—' : n(x));
  return (
    <div className="grid grid-cols-2 gap-3 sm:gap-6 lg:grid-cols-4">
      <StatCard icon="users" label="المشتركون" value={v(stats.subscribers)} unit={stats.subscribers != null ? unitWord(stats.subscribers, W.student) : undefined} hint="اشتراكات سارية" />
      <StatCard icon="aup" label="ذهاب الغد" value={v(stats.riders_departure)} unit={stats.riders_departure != null ? unitWord(stats.riders_departure, W.rider) : undefined} hint={`في ${countOf(going, W.trip, 'رحلة واحدة')}`} />
      <StatCard icon="adown" label="عودة الغد" value={v(stats.riders_return)} unit={stats.riders_return != null ? unitWord(stats.riders_return, W.rider) : undefined} hint={`في ${countOf(back, W.time, 'موعد واحد')}`} />
      {stats.bus_capacity
        ? <StatCard icon="bus" label="مقاعد الباص" value={stats.bus_capacity} unit={unitWord(stats.bus_capacity, W.seat)}
          hint={<>لكل رحلة{online && <> · <Link to={editTo} className="text-teal hover:underline">تعديل</Link></>}</>} />
        : <StatCard icon="bus" label="مقاعد الباص" value="—" hint={<Link to={editTo} className="text-teal hover:underline">لم تُحدد · حدّدها</Link>} />}
    </div>
  );
};

const PricesCard: React.FC<{ line: LineRow; sold: Record<string, boolean> | null; daily: boolean; companyId: string; editTo: string; online: boolean }> = ({ line, sold, daily, companyId, editTo, online }) => {
  const rows = SALE_OPTIONS.map((o) => {
    const p = line.line_period_prices.find((x) => x.option === o);
    const price = p && Number(p.price) > 0 ? Number(p.price) : null;
    const allowed = sold ? sold[o] : true;
    const on = !!p?.is_enabled && price != null;
    return { key: o, label: optionName[o], price, badge: !on ? <Badge><span className="sm:hidden">لا يُباع</span><span className="hidden sm:inline">لا يُباع على هذا الخط</span></Badge> : allowed ? <Badge tone="success">يُباع</Badge> : <Badge tone="warning">أوقفته إدارة باصك</Badge> };
  });
  rows.push({ key: 'daily' as never, label: 'اليومي (نقداً)', price: Number(line.price_daily) > 0 ? Number(line.price_daily) : null,
    badge: Number(line.price_daily) > 0 ? (daily ? <Badge tone="success">يُباع</Badge> : <Badge tone="warning">أوقفته إدارة باصك</Badge>) : <Badge>لا يُباع</Badge> });
  return (
    <Card className="px-5 pb-4 pt-5">
      <div className="mb-2 flex items-center gap-3">
        <h2 className="m-0 flex-1 text-card">الأسعار على هذا الخط</h2>
        <EditLink to={editTo} disabled={!online}>تعديل الأسعار</EditLink>
      </div>
      <dl className="m-0">
        {rows.map((r, i) => (
          <div key={r.key} className={`flex min-h-11 items-center gap-3 py-1.5 ${i ? 'border-t border-hair' : ''}`}>
            <dt className="min-w-0 flex-1 text-small text-ink-2">{r.label}</dt>
            <dd className="m-0 w-[84px] flex-none text-small font-semibold sm:w-[110px]">{r.price != null ? <Money value={r.price} /> : <span className="font-normal text-ink-2">بلا سعر</span>}</dd>
            <dd className="m-0 flex flex-none justify-end sm:w-[150px]">{r.badge}</dd>
          </div>
        ))}
      </dl>
      <p className="m-0 mt-3 text-label text-ink-2">السعر ومفتاح البيع هنا. تواريخ كل فصل تُحدد في <Link to={`/c/${companyId}/subscription-periods`} className="font-semibold text-teal hover:underline">مواعيد الاشتراك</Link>.</p>
    </Card>
  );
};

const SupervisorsCard: React.FC<{ sups: { id: string; full_name: string; phone: string; is_active: boolean }[]; companyId: string }> = ({ sups, companyId }) => (
  <Card className="px-5 pb-4 pt-5">
    <div className="mb-2 flex items-center gap-3">
      <h2 className="m-0 flex-1 text-card">مشرفو الخط</h2>
      <EditLink to={`/c/${companyId}/supervisors`}>تعيين مشرف</EditLink>
    </div>
    {sups.length === 0 ? <p className="m-0 py-2 text-small text-ink-2">لا مشرف على هذا الخط بعد. بدون مشرف لا يُسجَّل صعود الطلاب.</p> : (
      <ul className="m-0 flex list-none flex-col gap-3 p-0">
        {sups.map((s) => (
          <li key={s.id} className="flex items-center gap-3">
            <span aria-hidden="true" className="flex h-10 w-10 flex-none items-center justify-center rounded-full bg-teal-tint text-card text-teal">{s.full_name.trim().charAt(0)}</span>
            <span className="flex min-w-0 flex-1 flex-col"><span className="truncate text-small font-semibold">{s.full_name}</span><Ltr className="self-start text-label text-ink-2">{phoneText(s.phone)}</Ltr></span>
            {!s.is_active && <StatePill state="off" />}
          </li>
        ))}
      </ul>
    )}
    <p className="m-0 mt-3 text-label text-ink-2">المشرف يركب مع الباص ويسجّل صعود الطلاب. المتوقف لا يرى خطوطه ولا يسجّل الركوب.</p>
  </Card>
);
