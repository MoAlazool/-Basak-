import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button, Card, Dialog, Note, Page, PageHeader, PhoneBar, Stepper, errorText, useOnline } from '../../ui';
import { useCompany } from '../../lib/adminScope';
import { useGuard } from '../../lib/guard';
import { notify } from '../../lib/toasts';
import { clockLabel } from '../../lib/time';
import { useSupervisorLines, useUniversities, type LineRow } from '../../lib/reference';
import { afterLineSaved, PartialSaveError, saveLine, statsFor, useLinesStats, useSaleContext } from '../../lib/linesData';
import {
  buildSavePayload, changeCount, draftFromLine, draftIssues, editEffects, emptyDraft, hasTyped, joinAnd, typedSummary, unitWord,
  unsavedText, W, type LineDraft, type StepNo, type TripDraft,
} from '../../lib/lines';
import { SALE_OPTIONS } from '../../lib/saleOptions';
import { STEPS, StepsRow, Step1, Step2, Step4, Step5, StepsNav, Summary, UnsavedBadge } from './WizardSteps';
import { TripsStep } from './TripsStep';
import { useLeaveGuard } from './useLeaveGuard';

const QUESTIONS = [
  'ما اسم الخط، وإلى أي جامعات يوصل؟', 'من أين يركب الطلاب؟ اكتب المحطات بترتيب مرور الباص.',
  'متى يتحرك الباص في الذهاب، ومتى يعود من الجامعة؟', 'اكتب سعر كل اشتراك تبيعه على هذا الخط.',
];
const B: React.FC<{ children: React.ReactNode }> = ({ children }) => <b className="font-semibold text-ink">{children}</b>;
const students = (n: number) => `${n.toLocaleString('en-US')} ${unitWord(n, W.student)}`;

type Ask =
  | { kind: 'leave'; go: () => void }
  | { kind: 'station'; key: string; name: string; n: number }
  | { kind: 'trip'; t: TripDraft; n: number }
  | { kind: 'save' };

/**
 * A line built (or edited) in five steps: name and universities, stations,
 * trips, prices, review. Nothing is saved before the last step, and then in ONE
 * request (save_line_full). Leaving with something typed asks first.
 * docs/canvas/AdmLineNew1..5, AdmLineEdit, AdmLineStepDialogs, AdmLineSaveError, AdmLineLeavePhone.
 */
export const LineWizard: React.FC<{ mode: 'new' | 'edit'; line?: LineRow; startStep?: StepNo }> = ({ mode, line, startStep = 1 }) => {
  const edit = mode === 'edit';
  const company = useCompany();
  const navigate = useNavigate();
  const online = useOnline();
  const guard = useGuard();
  const sale = useSaleContext(company.id);
  const universities = useUniversities().data;
  const statsQ = useLinesStats(company.id);
  const stats = line ? statsFor(statsQ.data, line.id) : null;
  const assignments = useSupervisorLines(company.id).data;
  const uniName = useMemo(() => { const m = new Map((universities ?? []).map((u) => [u.id, u.name])); return (id: string) => m.get(id) ?? 'جامعة'; }, [universities]);

  const [saved, setSaved] = useState<LineDraft>(() => (line ? draftFromLine(line, stats?.bus_capacity) : emptyDraft(company.id, sale.defaults ?? undefined, sale.dailyDefault ?? true)));
  const [d, setD] = useState<LineDraft>(saved);
  const [step, setStep] = useState<StepNo>(startStep);
  const [reached, setReached] = useState<number>(edit ? 5 : startStep);
  const [left, setLeft] = useState<Set<number>>(() => new Set(edit ? [] : []));
  const [tried, setTried] = useState(false);
  const [openTrip, setOpenTrip] = useState<string | null>(null);
  const [ask, setAsk] = useState<Ask | null>(null);
  const [saving, setSaving] = useState(false);
  const [failure, setFailure] = useState<{ partial: boolean; text: string } | null>(null);
  const savedId = useRef<string | null>(line?.id ?? null);
  const leaving = useRef(false);
  const touchedPrices = useRef(false);
  const touchedSeats = useRef(false);
  const patch = (fn: (x: LineDraft) => LineDraft) => setD((cur) => {
    const next = fn(cur);
    if (next.prices !== cur.prices || next.daily_enabled !== cur.daily_enabled) touchedPrices.current = true;
    if (next.capacity !== cur.capacity) touchedSeats.current = true;
    return next;
  });

  // What arrives after the first frame: what a new line starts with (the company's switches), the bus seats.
  useEffect(() => {
    if (edit || !sale.defaults || touchedPrices.current) return;
    const on = sale.defaults; const daily = sale.dailyDefault ?? true;
    const apply = (x: LineDraft) => ({ ...x, daily_enabled: daily, prices: Object.fromEntries(SALE_OPTIONS.map((o) => [o, { ...x.prices[o], enabled: on[o] }])) as LineDraft['prices'] });
    setD(apply); setSaved(apply);
  }, [edit, sale.defaults, sale.dailyDefault]);
  useEffect(() => {
    if (!edit || touchedSeats.current || stats?.bus_capacity == null) return;
    const v = String(stats.bus_capacity);
    setD((x) => ({ ...x, capacity: v })); setSaved((x) => ({ ...x, capacity: v }));
  }, [edit, stats?.bus_capacity]);

  const ctx = useMemo(() => ({ sold: sale.sold, daily: sale.daily, uniName }), [sale.sold, sale.daily, uniName]);
  const issues = useMemo(() => draftIssues(d, ctx), [d, ctx]);
  const changes = useMemo(() => (edit ? changeCount(saved, d) : 0), [edit, saved, d]);
  const dirty = edit ? changes > 0 : hasTyped(d);
  const back = line ? `/c/${company.id}/lines/${line.id}` : `/c/${company.id}/lines`;
  const title = edit ? `تعديل خط ${line!.name}` : 'خط جديد';

  useLeaveGuard(dirty && !leaving.current, back, (go) => setAsk({ kind: 'leave', go }));
  const close = () => (dirty ? setAsk({ kind: 'leave', go: () => navigate(back) }) : navigate(back));

  const go = (s: StepNo) => {
    setLeft((x) => new Set(x).add(step));
    setStep(s);
    setReached((r) => Math.max(r, s));
    window.scrollTo({ top: 0 });
  };
  const show = (s: number) => tried || left.has(s) || (edit && changes > 0 && step !== s);

  const removeStation = (key: string) => {
    const s = d.stations.find((x) => x.key === key)!;
    const n = edit && s.id ? stats?.station_subscribers[s.id] ?? 0 : 0;
    if (n > 0) { setAsk({ kind: 'station', key, name: s.name, n }); return; }
    dropStation(key);
  };
  const dropStation = (key: string) => patch((c) => ({
    ...c, stations: c.stations.filter((s) => s.key !== key),
    trips: c.trips.map((t) => { const times = { ...t.times }; delete times[key]; return { ...t, times }; }),
  }));
  const removeTrip = (t: TripDraft) => {
    const n = edit && t.id ? stats?.trip_subscribers[t.id] ?? 0 : 0;
    if (n > 0) { setAsk({ kind: 'trip', t, n }); return; }
    dropTrip(t.key);
  };
  const dropTrip = (key: string) => patch((c) => ({ ...c, trips: c.trips.filter((x) => x.key !== key) }));

  const effects = useMemo(() => (edit && stats ? editEffects(saved, d, stats.station_subscribers, stats.trip_subscribers) : []), [edit, stats, saved, d]);

  const requestSave = () => {
    setTried(true);
    if (issues.length) { go(5); return; }
    if (edit && effects.length) { setAsk({ kind: 'save' }); return; }
    void save();
  };
  const save = () => guard('save', async () => {
    setSaving(true); setFailure(null);
    const payload = buildSavePayload({ ...d, id: savedId.current ?? undefined });
    try {
      const id = await saveLine(payload);
      savedId.current = id;
      leaving.current = true;
      setAsk(null);
      await afterLineSaved(company.id, id, [...d.stations.map((s) => s.id), ...d.trips.map((t) => t.id)]);
      void statsQ.reload();
      notify(edit ? { title: `حُفظت تعديلات خط ${line!.name}`, tone: 'success' } : { title: `حُفظ خط ${payload.name || payload.stations[0]?.name}`, body: 'يراه الطلاب الآن في التطبيق.', tone: 'success' });
      navigate(`/c/${company.id}/lines/${id}`, { replace: true });
    } catch (error) {
      setAsk(null);
      if (error instanceof PartialSaveError) {
        savedId.current = error.lineId;
        setFailure({ partial: true, text: 'حُفظت المحطات والرحلات، ولم نستطع حفظ الأسعار وعدد المقاعد. الخط لن يظهر للطلاب حتى تكتمل. بياناتك كلها كما كتبتها هنا: حاول مرة أخرى، ولن يتكرر الخط.' });
      } else {
        setFailure({ partial: false, text: `${errorText(error)} لم يُحفظ شيء، وبياناتك كلها كما كتبتها هنا.` });
      }
      setStep(5);
    } finally {
      setSaving(false);
    }
  });

  const unsaved = edit ? unsavedText(changes) : '';
  const tripIssues = issues.filter((i) => i.step === 3 && i.tripKey).length;
  const hint = step === 5
    ? (issues.length ? (issues.length === 1 ? 'أكمل الأمر الباقي ليعمل زر الحفظ' : issues.length === 2 ? 'أكمل الأمرين ليعمل زر الحفظ' : `أكمل ${issues.length} ${issues.length <= 10 ? 'أمور' : 'أمراً'} ليعمل زر الحفظ`) : edit && changes ? unsaved : '')
    : edit ? (changes ? unsaved : '')
      : step === 3 && tripIssues ? `في ${tripIssues === 1 ? 'رحلة واحدة' : tripIssues === 2 ? 'رحلتين' : `${tripIssues} رحلات`} مشكلة. تستطيع المتابعة وإصلاحها قبل الحفظ.` : '';
  const saveLabel = failure ? 'إعادة المحاولة' : edit ? 'حفظ التعديلات' : 'حفظ الخط';
  const canSave = online && issues.length === 0 && (!edit || changes > 0 || !!failure);
  const primary = step === 5 || edit
    ? <Button key="p" icon={failure ? 'refresh' : 'check'} loading={saving} disabled={!canSave} onClick={requestSave}>{saveLabel}</Button>
    : <Button key="p" iconEnd="arrowFwd" onClick={() => go((step + 1) as StepNo)}>{STEPS[step - 1].next}</Button>;
  const prev = step > 1 ? <Button kind="secondary" icon="arrowBack" onClick={() => go((step - 1) as StepNo)}>السابق</Button> : null;

  const unis = d.university_ids.map(uniName);
  const hasSupervisor = !!line && (assignments ?? []).some((a) => a.line_id === line.id);
  const after: React.ReactNode[] = edit ? [
    'يرى طلاب الخط ما تغيّر في التطبيق فور الحفظ، ويتغيّر موعد ركوب من تغيّر موعد رحلته.',
    ...(hasSupervisor ? [] : ['ليس له مشرف بعد: عيّنه من صفحة «المشرفون» ليسجّل صعود الطلاب.']),
  ] : [
    `يظهر الخط في التطبيق${unis.length ? ` لطلاب ${joinAnd(unis)}` : ''}، بالاشتراكات المعروضة للبيع الآن.`,
    'ليس له مشرف بعد: عيّنه من صفحة «المشرفون» ليسجّل صعود الطلاب.',
  ];
  const saveError = failure && (
    <Note tone="danger" title={failure.partial ? 'لم يكتمل حفظ الخط' : edit ? 'لم تُحفظ التعديلات' : 'لم يُحفظ الخط'}
      action={<Button sm icon="refresh" onClick={requestSave} loading={saving} disabled={!online} className="hidden sm:inline-flex">إعادة المحاولة</Button>}>{failure.text}</Note>
  );

  const body = step === 1 ? <Step1 d={d} patch={patch} universities={universities ?? []} issues={issues.filter((i) => i.step === 1)} show={show(1)} />
    : step === 2 ? <Step2 d={d} patch={patch} uniName={uniName} onRemove={removeStation} counts={edit ? stats?.station_subscribers ?? {} : null} issues={issues.filter((i) => i.step === 2)} show={show(2)} />
      : step === 3 ? <TripsStep d={d} patch={patch} uniName={uniName} onRemove={removeTrip} show={show(3)} open={openTrip} setOpen={setOpenTrip} />
        : step === 4 ? <Step4 d={d} patch={patch} ctx={ctx} companyId={company.id} show={show(4)} />
          : <Step5 d={d} issues={issues} uniName={uniName} go={go} edit={edit} supervised={hasSupervisor} saveError={saveError} after={after} />;

  const stepperSteps = STEPS.map((s, i) => ({ label: s.label, state: (i + 1 === step ? 'current' : edit || i + 1 < reached ? 'done' : 'todo') as 'current' | 'done' | 'todo' }));
  const subscribers = stats?.subscribers ?? 0;

  return (
    <Page>
      <PageHeader title={title} back={{ label: 'الخطوط', to: back }} phoneActions={false}
        sub={<span className="hidden sm:inline">{edit ? 'انتقل بين الخطوات كما تشاء. لا يتغيّر شيء عند الطلاب حتى تضغط «حفظ التعديلات».' : 'خمس خطوات. لا يُحفظ شيء ولا يراه الطلاب حتى تضغط «حفظ الخط» في آخر خطوة.'}</span>}
        actions={<Button kind="outline" icon="x" onClick={close}>إغلاق</Button>} />
      {edit && subscribers > 0 && (
        <Note tone="warning" title={`للخط ${students(subscribers)}: ما تغيّره يصلهم`}>
          تغيير اسم محطة أو موعدها يظهر عند طلابها فور الحفظ، ويتغيّر موعد الركوب في اشتراكاتهم. محطة أو رحلة عليها طلاب لا تُحذف: تتوقف وتختفي من الخط، ويبقى طلابها عليها حتى تنقلهم. الاسم، الجامعات، المقاعد، الأسعار والمحطات والرحلات الخالية تتغيّر بحرية.
        </Note>
      )}
      <div className="sm:hidden"><Stepper steps={stepperSteps} /></div>
      <div className="hidden sm:block lg:hidden"><StepsRow step={step} reached={reached} edit={edit} go={go} /></div>
      <div className="grid grid-cols-1 items-start gap-6 lg:grid-cols-[208px_minmax(0,1fr)_292px]">
        <div className="hidden lg:block"><StepsNav step={step} d={d} reached={reached} edit={edit} go={go} /></div>
        <div className="flex min-w-0 flex-col gap-3">
          <h2 className="m-0 text-card sm:hidden">{step < 5 ? QUESTIONS[step - 1] : 'نظرة أخيرة. هنا فقط يُحفظ الخط.'}</h2>
          <Card as="section" className="flex flex-col">
            <header className="hidden border-b border-hair px-6 pb-4 pt-5 sm:block">
              <div className="text-cap text-ink-2">الخطوة {step} من 5</div>
              <h2 className="m-0 text-section">{STEPS[step - 1].label}</h2>
              <p className="m-0 text-small text-ink-2">{step < 5 ? QUESTIONS[step - 1] : edit ? 'نظرة أخيرة. هنا فقط تُحفظ التعديلات.' : 'نظرة أخيرة. هنا فقط يُحفظ الخط.'}</p>
            </header>
            <div className="p-4 sm:p-6">{body}</div>
            <footer className="hidden items-center gap-3 border-t border-hair px-6 py-4 sm:flex">
              {prev}
              <span className="flex-1" />
              {hint && <span className="max-w-[260px] text-label text-ink-2">{hint}</span>}
              {edit && step < 5 && <Button kind="outline" iconEnd="arrowFwd" className="lg:hidden" onClick={() => go((step + 1) as StepNo)}>{STEPS[step - 1].next}</Button>}
              {primary}
            </footer>
          </Card>
        </div>
        <div className="hidden lg:block"><Summary d={d} uniName={uniName} badge={<UnsavedBadge edit={edit} dirty={dirty} />} /></div>
      </div>
      <PhoneBar>
        {edit ? (
          // Editing: «حفظ التعديلات» on every step, the steps around it one tap away.
          <div className="flex gap-2">
            {prev && <div className="flex-none">{prev}</div>}
            {step < 5 && <Button kind="outline" iconEnd="arrowFwd" onClick={() => go((step + 1) as StepNo)}>التالي</Button>}
            <div className="min-w-0 flex-1 [&>*]:w-full">{primary}</div>
          </div>
        ) : (
          <div className="flex gap-2">
            {prev && <div className="flex-none">{prev}</div>}
            <div className="flex-1 [&>*]:w-full">
              {step === 5 ? primary : <Button iconEnd="arrowFwd" full onClick={() => go((step + 1) as StepNo)}>{STEPS[step - 1].next}</Button>}
            </div>
          </div>
        )}
      </PhoneBar>

      <Dialog open={ask?.kind === 'leave'} onClose={() => setAsk(null)} icon="alert" tone="warning"
        title={edit ? 'إغلاق دون حفظ التعديلات؟' : 'إغلاق دون حفظ الخط؟'}
        actions={[<Button key="c" kind="secondary" data-autofocus onClick={() => setAsk(null)}>رجوع إلى الخط</Button>,
          <Button key="ok" kind="dangerQuiet" onClick={() => { const a = ask; leaving.current = true; setAsk(null); if (a?.kind === 'leave') a.go(); }}>إغلاق دون حفظ</Button>]}>
        <p className="m-0">{edit
          ? `لم تُحفظ تعديلاتك على خط ${line?.name} (${unsavedText(changes).split(' لم')[0]}). إن أغلقت الآن ضاعت، وبقي الخط كما كان.`
          : `كتبت ${typedSummary(d) || 'بعض البيانات'}، ولم يُحفظ شيء منها بعد. إن أغلقت الآن ضاع ما كتبته.`}</p>
      </Dialog>

      {ask?.kind === 'station' && (
        <Dialog open onClose={() => setAsk(null)} icon="trash" tone="danger" title={`إزالة محطة «${ask.name}»؟`}
          actions={[<Button key="c" kind="secondary" data-autofocus onClick={() => setAsk(null)}>رجوع</Button>,
            <Button key="ok" kind="danger" onClick={() => { dropStation(ask.key); setAsk(null); }}>إزالة المحطة</Button>]}>
          <p className="m-0"><B>{students(ask.n)}</B> اشتراكهم من هذه المحطة. لن تُحذف: تختفي من الخط ولا يختارها طالب جديد، وتسقط مواعيدها من كل الرحلات.</p>
          <p className="m-0">هؤلاء الطلاب يبقون مسجلين عليها بلا موعد مرور. أبلغهم أين يركبون قبل أن تحفظ.</p>
        </Dialog>
      )}
      {ask?.kind === 'trip' && (
        <Dialog open onClose={() => setAsk(null)} icon="trash" tone="danger" title={`حذف ${ask.t.direction === 'return' ? 'موعد العودة' : 'رحلة'} ${clockLabel(ask.t.start_time)}؟`}
          actions={[<Button key="c" kind="secondary" data-autofocus onClick={() => setAsk(null)}>رجوع</Button>,
            <Button key="ok" kind="danger" onClick={() => { dropTrip(ask.t.key); setAsk(null); }}>{ask.t.direction === 'return' ? 'حذف الموعد' : 'حذف الرحلة'}</Button>]}>
          <p className="m-0"><B>{students(ask.n)}</B> مشتركون على {ask.t.direction === 'return' ? 'هذا الموعد' : 'هذه الرحلة'}. لن {ask.t.direction === 'return' ? 'يُحذف: يتوقف ولا يظهر' : 'تُحذف: تتوقف ولا تظهر'} لطالب جديد.</p>
          <p className="m-0">هؤلاء الطلاب يبقون عليها في اشتراكاتهم. أبلغهم بالرحلة البديلة قبل أن تحفظ.</p>
        </Dialog>
      )}
      {ask?.kind === 'save' && (
        <Dialog open onClose={() => !saving && setAsk(null)} icon="check" tone="teal" title={`حفظ تعديلات خط ${line?.name}؟`}
          actions={[<Button key="c" kind="secondary" data-autofocus disabled={saving} onClick={() => setAsk(null)}>رجوع</Button>,
            <Button key="ok" loading={saving} disabled={!online} onClick={() => void save()}>حفظ التعديلات</Button>]}>
          {effects.map((e, i) => (
            <p key={i} className="m-0">{e.kind === 'times'
              ? <>تغيّر موعد رحلة {clockLabel(e.trip)} على {e.stations === 1 ? 'محطة واحدة' : e.stations === 2 ? 'محطتين' : `${e.stations} ${unitWord(e.stations, W.station)}`}: <B>{students(e.students)}</B> يتغيّر موعد ركوبهم في التطبيق فور الحفظ.</>
              : e.kind === 'station' ? <>أُزيلت محطة «{e.name}» وعليها {students(e.students)}.</>
                : <>{e.direction === 'return' ? 'حُذف موعد العودة' : 'حُذفت رحلة'} {clockLabel(e.trip)} وعليها {students(e.students)}.</>}</p>
          ))}
          <p className="m-0">إن أردت إبلاغهم فأرسل لهم إشعاراً من صفحة «الإشعارات» بعد الحفظ.</p>
        </Dialog>
      )}
    </Page>
  );
};
