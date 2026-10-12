import React, { Suspense, lazy, useMemo } from 'react';
import {
  AttentionList, Badge, Button, Note, ErrorState, Page, PageHeader, PhoneBar, Section, SkeletonList, SkeletonStat, SkeletonTable, StatCard,
  cairo, clock, countText, dayText, num, NOUN, useOnline,
} from '../ui';
import { useAdminScope, useCompany } from '../lib/adminScope';
import { SUBSCRIBER, companyAttention, isFirstRun, nOf, rideDayText, ridersTitle, useCompanyToday, type CompanyToday } from '../lib/today';

const loadLinesTable = () => import('../components/today/LinesTable');
// Asked for as soon as this page's code runs, so it arrives together with the data.
void loadLinesTable().catch(() => undefined);
const LinesTable = lazy(() => loadLinesTable().then((m) => ({ default: m.LinesTable })));
// «أهم التوصيات» reads «التحليلات», so its code and data come after the page.
const TodayInsights = lazy(() => import('../components/today/TodayInsights'));
const FirstRun = lazy(() => import('../components/today/FirstRun').then((m) => ({ default: m.FirstRun })));

/** «اليوم» — the company admin's first page (docs/canvas/AdmToday, AdmTodayPhone, AdmTodayStates, AdmTodayNew, AdmTodayNewPhone). */
export const TodayPage: React.FC = () => {
  const company = useCompany();
  const base = `/c/${company.id}`;
  const { data, loading, error, updatedAt, refresh } = useCompanyToday(company.id);
  const online = useOnline();
  const today = data?.today ?? cairo(new Date()).day;

  const platformAdmin = useAdminScope().role === 'super_admin';
  const stopped = company.status !== 'active';
  if (data && isFirstRun(data) && !stopped) return <Suspense fallback={<Page><PageHeader title="اليوم" sub={dayText(today, { weekday: true })} /><SkeletonList rows={3} /></Page>}><FirstRun data={data} base={base} /></Suspense>;

  const notify = (phone?: boolean) => (
    <Button kind="outline" icon="megaphone" to={`${base}/notifications`} disabled={!online} full={phone}>إرسال إشعار للطلاب</Button>
  );
  return (
    <Page>
      <PageHeader title="اليوم" sub={dayText(today, { weekday: true })} actions={!data && error ? undefined : notify()} phoneActions={false} />
      {!data && error ? (
        <ErrorState card title="تعذّر تحميل صفحة اليوم" text="لم نستطع جلب الإيصالات وأعداد الركاب. تأكد من اتصالك ثم حاول مرة أخرى." onRetry={refresh} />
      ) : (
        <>
          {/* The platform admin inside a company (AdmPlatWsToday, AdmPlatWsSuspended). */}
          {stopped ? (
            <Note tone="warning" title={company.status === 'archived' ? 'هذه الشركة مؤرشفة' : 'هذه الشركة موقوفة'}
              action={<Button kind="link" sm to="/platform/companies">أعد تشغيلها من «الشركات»</Button>}>
              مديروها ومشرفوها لا يدخلون، وطلابها لا يرونها في التطبيق. أنت وحدك تراها. بياناتها كما كانت يوم الإيقاف.
            </Note>
          ) : platformAdmin && (
            <Note tone="teal" icon="shield" title="تعمل هنا كمدير لهذه الشركة">ترى ما يراه مديرها وتستطيع كل ما يستطيعه. ما تقبله أو تغيّره يصل طلابها فوراً.</Note>
          )}
          <Riders data={data} loading={loading} base={base} />
          <div className="grid grid-cols-1 gap-5 sm:gap-6 lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)]">
            <Attention data={data} base={base} stale={!online && !!updatedAt ? updatedAt : 0} loading={loading} stopped={stopped} />
            {!stopped && <Suspense fallback={<SkeletonList rows={3} />}><TodayInsights base={base} companyId={company.id} /></Suspense>}
          </div>
          {loading ? <SkeletonTable rows={6} cols={7} /> : data && <Suspense fallback={<SkeletonTable rows={6} cols={7} />}><LinesTable data={data} base={base} /></Suspense>}
          {data && <PhoneBar>{notify(true)}</PhoneBar>}
        </>
      )}
    </Page>
  );
};

/* ── يحتاج منك الآن ─────────────────────────────────────────────────── */
const Attention: React.FC<{ data: CompanyToday | null; base: string; stale: number; loading: boolean; stopped?: boolean }> = ({ data, base, stale, loading, stopped }) => {
  const items = useMemo(() => (data && !stopped ? companyAttention(data, { base }) : []), [data, base, stopped]);
  return (
    <Section title="يحتاج منك الآن"
      meta={data && items.length > 0 ? <Badge>{countText(items.length, NOUN.item)}</Badge> : undefined}
      end={stale ? <span className="text-label text-ink-3">آخر تحديث {clock(cairo(new Date(stale)).time)}</span> : undefined}>
      {loading || !data ? <SkeletonList rows={4} /> : <AttentionList items={items.map((a, i) => ({ ...a, primary: i === 0 }))}
        {...(stopped ? { zeroTitle: 'لا شيء يتحرك في شركة موقوفة', zeroSub: 'لا إيصالات جديدة ولا طلبات حتى يُعاد تشغيلها.' } : {})} />}
    </Section>
  );
};

/* ── ركاب الغد: the day's numbers in one row ─────────────────────────── */
const Riders: React.FC<{ data: CompanyToday | null; loading: boolean; base: string }> = ({ data, loading, base }) => {
  if (loading || !data) {
    return <div className="grid grid-cols-2 gap-3 sm:gap-6 lg:grid-cols-4"><SkeletonStat /><SkeletonStat /><SkeletonStat /><SkeletonStat /></div>;
  }
  const riding = data.lines.filter((l) => l.going > 0).length;
  const share = data.subscribers > 0 ? Math.round((data.confirmed / data.subscribers) * 100) : 0;
  const voteLine = data.vote_open === false && data.vote_opens_at
    ? `يبدأ التأكيد ${clock(data.vote_opens_at)}`
    : data.vote_closes_at ? `التأكيد مفتوح حتى ${clock(data.vote_closes_at)}` : 'التأكيد مفتوح';
  const when = ridersTitle(data.today, data.ride_date) === 'ركاب اليوم' ? 'اليوم' : 'الغد';
  const day = rideDayText(data.ride_date);
  return (
    <section aria-label={`${ridersTitle(data.today, data.ride_date)} · ${day}`} className="grid grid-cols-2 gap-3 sm:gap-6 lg:grid-cols-4">
      <StatCard label="المشتركون" icon="users" value={num(data.subscribers)} to={`${base}/students`}
        hint={data.members > data.subscribers ? `من ${num(data.members)} طالباً في الشركة` : 'اشتراكات سارية'} />
      <StatCard label={`ذهاب ${when}`} icon="aup" value={num(data.going)} unit="راكباً"
        hint={`${day} · ${riding === 0 ? 'لم يؤكد أحد بعد' : riding === 1 ? 'في خط واحد' : `في ${countText(riding, NOUN.line)}`}`} />
      <StatCard label={`عودة ${when}`} icon="adown" value={num(data.returning)} unit="راكباً" hint={`${day} · من الجامعات`} />
      <StatCard label="أكّدوا الركوب" icon="check" value={num(data.confirmed)} bar={share}
        unit={<>من {nOf(data.subscribers, SUBSCRIBER)} · <span dir="ltr" className="tabular [unicode-bidi:isolate]">{share}%</span></>}
        hint={`${voteLine} · الأعداد تتغيّر`} />
    </section>
  );
};

