import React, { useEffect, useMemo, useState } from 'react';
import { Button } from '../../ui/Button';
import { ErrorState, Note, SkeletonForm, useOnline } from '../../ui/Feedback';
import { FieldRow, PasswordField, RadioCards, SelectField, TextField } from '../../ui/Field';
import { Icon } from '../../ui/Icon';
import { FormSection, InfoRows, Page, PageHeader, PhoneBar, Stepper, type Step } from '../../ui/Layout';
import { Dialog } from '../../ui/Overlay';
import { Ltr, Money } from '../../ui/Status';
import { clock, errorText, moneyText, phoneText } from '../../ui/format';
import { supabase } from '../../lib/supabase';
import { invokeEdgeFunction } from '../../lib/edgeFunctions';
import { keys, refreshIfNotUpdated, STALE, unwrap, usePageData } from '../../lib/query';
import { activeStations, switchesKey, useLineOptions } from '../../lib/reference';
import type { LineOption, TripOption } from '../../lib/lineOptions';
import { useGuard } from '../../lib/guard';
import { notify } from '../../lib/toasts';
import { isPhoneRefusal, phoneDigits, shortName, studentProblems } from '../../lib/students';

interface Period { period_code: string; academic_year: number; label: string; subscription_type: string; start_date: string; end_date: string; phase: 'current' | 'upcoming' }
type SubType = 'termly' | 'yearly' | 'daily';

// Active trips of a line open to this university (or to every university).
const tripsServing = (line: LineOption | undefined, direction: 'departure' | 'return', universityId: string) =>
  (line?.line_trips ?? []).filter((trip) => trip.is_active && trip.direction === direction && (!trip.university_id || trip.university_id === universityId));
// Departures that stop at the station, with the stop time there; returns leave the
// university at their start time and serve every station (validate_subscription_station_times).
const stopOptions = (line: LineOption | undefined, direction: 'departure' | 'return', stationId: string, universityId: string) =>
  tripsServing(line, direction, universityId)
    .map((trip) => ({ trip, time: direction === 'return' ? trip.start_time : trip.line_trip_stops.find((stop) => stop.station_id === stationId)?.stop_time }))
    .filter((o): o is { trip: TripOption; time: string } => !!o.time)
    .sort((a, b) => a.time.localeCompare(b.time));
const servesUniversity = (line: LineOption, universityId: string) => tripsServing(line, 'departure', universityId).length > 0;

const EMPTY = { fullName: '', phone: '', universityId: '', password: '', lineId: '', stationId: '', departureTripId: '', returnTripId: '', type: 'termly' as SubType, periodKey: '' };
type Draft = typeof EMPTY;

/**
 * «إضافة طالب» in three steps, nothing saved before the last (docs/canvas/AdmStudentAdd1–3,
 * AdmStudentAddOutcomes, AdmStudentAddInvitedPhone, AdmStudentDialogs · Leave).
 */
export const AddStudentFlow: React.FC<{
  companyId: string; companyName: string; back: string;
  onLeave: () => void; onOpenStudent: (id: string) => void; onShowInvites: () => void;
}> = ({ companyId, back, onLeave, onOpenStudent, onShowInvites }) => {
  const online = useOnline();
  const guard = useGuard();
  const [step, setStep] = useState(0);
  const [d, setD] = useState<Draft>(EMPTY);
  const [errors, setErrors] = useState<Partial<Record<keyof Draft, string>>>({});
  const [busy, setBusy] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [outcome, setOutcome] = useState<{ kind: 'created'; id: string; draft: Draft; period: string; line: string } | { kind: 'invited'; phone: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const set = (patch: Partial<Draft>) => { setD((x) => ({ ...x, ...patch })); setErrors((e) => { const n = { ...e }; Object.keys(patch).forEach((k) => delete n[k as keyof Draft]); return n; }); };
  const dirty = !!(d.fullName || d.phone || d.password || d.universityId);

  useEffect(() => {
    if (!dirty || outcome) return undefined;
    const warn = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [dirty, outcome]);

  const options = useLineOptions(companyId, true);
  const universities = options.data?.universities ?? [];
  const lines = useMemo(() => (options.data?.lines ?? []).filter((l) => l.company_id === companyId), [options.data, companyId]);
  const university = universities.find((u) => u.id === d.universityId);
  const serving = lines.filter((l) => servesUniversity(l, d.universityId));
  const line = serving.find((l) => l.id === d.lineId);
  const stations = activeStations(line);
  const station = stations.find((s) => s.id === d.stationId);
  const departures = stopOptions(line, 'departure', d.stationId, d.universityId);
  const returns = stopOptions(line, 'return', d.stationId, d.universityId);

  const periodsQuery = usePageData(keys.company(companyId, 'periods', d.lineId || 'none'), async () =>
    (d.lineId ? unwrap<Period[]>(supabase.rpc('get_purchasable_periods', { p_line_id: d.lineId })) : []), { enabled: !!d.lineId, staleTime: STALE.reference });
  const periods = useMemo(() => periodsQuery.data ?? [], [periodsQuery.data]);
  const switches = usePageData(switchesKey(companyId), () => unwrap<{ daily_effective?: boolean }>(supabase.rpc('get_subscription_switches', { p_company_id: companyId })), { staleTime: STALE.reference });
  const companyDaily = switches.data ? !!switches.data.daily_effective : true;
  // A line whose daily is switched off (price 0) sells no daily ride.
  const lineDaily = !line || Number(line.price_daily) > 0;
  const dailyOn = companyDaily && lineDaily;
  const yearlyOn = periods.some((p) => p.subscription_type === 'yearly');
  const periodsForType = periods.filter((p) => p.subscription_type === d.type);
  const periodKey = (p: Period) => `${p.period_code}:${p.academic_year}`;
  const period = periodsForType.find((p) => periodKey(p) === d.periodKey);
  const priceOf = (code: string) => line?.line_period_prices?.find((x) => x.option === (code === 'annual' ? 'both' : code))?.price ?? null;
  const price = d.type === 'daily' ? line?.price_daily ?? null : period ? priceOf(period.period_code) : null;

  // Choosing a university, a line or a station picks the first that fits after it.
  const pickLine = (lineId: string, uni = d.universityId) => {
    const l = lines.find((x) => x.id === lineId);
    const st = activeStations(l)[0];
    set({ lineId, stationId: st?.id ?? '', departureTripId: stopOptions(l, 'departure', st?.id ?? '', uni)[0]?.trip.id ?? '', returnTripId: stopOptions(l, 'return', st?.id ?? '', uni)[0]?.trip.id ?? '' });
  };
  const pickStation = (stationId: string) => set({ stationId, departureTripId: stopOptions(line, 'departure', stationId, d.universityId)[0]?.trip.id ?? '', returnTripId: stopOptions(line, 'return', stationId, d.universityId)[0]?.trip.id ?? '' });
  useEffect(() => {
    if (step !== 1 || !options.data) return;
    if (!line || !servesUniversity(line, d.universityId)) pickLine(serving[0]?.id ?? '');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, options.data, d.universityId]);
  useEffect(() => {
    if (d.type === 'yearly' && periods.length && !yearlyOn) set({ type: 'termly' });
    if (d.type === 'daily' && !dailyOn) set({ type: 'termly' });
    const first = periodsForType[0] ? periodKey(periodsForType[0]) : '';
    if (d.type !== 'daily' && !periodsForType.some((p) => periodKey(p) === d.periodKey) && d.periodKey !== first) set({ periodKey: first });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [periods, d.type, dailyOn]);

  const next = () => {
    if (step === 0) {
      const p = studentProblems(d);
      setErrors(p);
      if (Object.keys(p).length) { document.getElementById(`add-${Object.keys(p)[0]}`)?.focus(); return; }
      setStep(1);
    } else if (step === 1) {
      if (!line || !station || !d.departureTripId) return;
      setStep(2);
    }
    window.scrollTo({ top: 0 });
  };
  const prev = () => { setStep((s) => Math.max(0, s - 1)); window.scrollTo({ top: 0 }); };

  const submit = () => guard('add', async () => {
    if (!line || !station || !university) return;
    if (d.type !== 'daily' && !period) return;
    setBusy(true);
    try {
      const created = await invokeEdgeFunction<{ id?: string; invited?: boolean }>('admin-create-student', {
        fullName: d.fullName.trim().replace(/\s+/g, ' '), phone: phoneDigits(d.phone), university: university.name, password: d.password,
        lineId: line.id, stationId: station.id, subscriptionType: d.type, departureTripId: d.departureTripId, returnTripId: d.returnTripId || null,
        ...(d.type !== 'daily' && period ? { periodCode: period.period_code, academicYear: period.academic_year } : {}),
      });
      if (created?.invited) {
        refreshIfNotUpdated(keys.company(companyId, 'invites'));
        setOutcome({ kind: 'invited', phone: phoneDigits(d.phone) });
      } else {
        refreshIfNotUpdated(keys.company(companyId, 'students'));
        setOutcome({ kind: 'created', id: created?.id ?? '', draft: d, period: d.type === 'daily' ? 'الاشتراك اليومي' : period?.label ?? '', line: line.name });
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : '';
      if (isPhoneRefusal(message)) {
        setErrors({ phone: 'هذا الرقم لطالب في شركتك بالفعل، أو أُرسلت له دعوة. ابحث عنه في قائمة الطلاب أو في «الدعوات».' });
        setStep(0);
        window.setTimeout(() => document.getElementById('add-phone')?.focus(), 50);
      } else {
        const text = errorText(e);
        const network = text.startsWith('تعذّر الوصول') || text.startsWith('لا يوجد اتصال') || text.startsWith('حدث خطأ من جهتنا');
        notify({ title: network ? 'لم يُسجَّل الطالب. تأكد من اتصالك ثم حاول مرة أخرى.' : 'لم يُسجَّل الطالب.', body: network ? undefined : text, tone: 'error',
          action: { label: 'إعادة المحاولة', run: () => void submit() } }, 15_000);
      }
    } finally { setBusy(false); }
  });

  const restart = () => { setOutcome(null); setD(EMPTY); setErrors({}); setStep(0); setCopied(false); };
  const leave = () => (dirty && !outcome ? setLeaving(true) : onLeave());

  const steps: Step[] = ['الطالب', 'الخط والرحلات', 'الاشتراك'].map((label, i) => ({ label, state: i < step ? 'done' : i === step ? 'current' : 'todo' }));
  const tripLabel = (o: { trip: TripOption; time: string }) => (
    <span className="flex flex-wrap items-baseline gap-x-2"><span className="font-semibold">{clock(o.time)}</span>{o.trip.label && <span className="text-label font-normal text-ink-2">{o.trip.label}</span>}</span>
  );
  const depTime = departures.find((o) => o.trip.id === d.departureTripId)?.time;
  const retTime = returns.find((o) => o.trip.id === d.returnTripId)?.time;
  const tripsLine = [depTime && `ذهاب ${clock(depTime)}`, retTime && `عودة ${clock(retTime)}`].filter(Boolean).join(' · ');
  const canNext = step === 0 || (step === 1 && !!line && !!station && !!d.departureTripId);
  const canSave = !!line && !!station && !!d.departureTripId && (d.type === 'daily' || !!period) && online;

  const nav = (phone: boolean) => (
    <>
      {!phone && <Button kind="link" onClick={leave} className="me-auto">إلغاء</Button>}
      {step > 0 && <Button kind="secondary" icon={phone ? undefined : 'back'} onClick={prev} className={phone ? 'flex-1' : ''}>السابق</Button>}
      {step < 2
        ? <Button iconEnd="fwd" disabled={!canNext} onClick={next} className={phone ? 'flex-[2]' : ''} full={phone && step === 0}>التالي</Button>
        : <Button icon="check" loading={busy} disabled={!canSave} onClick={() => void submit()} className={phone ? 'flex-[2]' : ''}>تسجيل الطالب</Button>}
    </>
  );

  return (
    <Page>
      <div className="flex w-full max-w-[920px] flex-col gap-4 sm:gap-4">
        <PageHeader title="إضافة طالب" back={{ label: 'الطلاب', to: back }} sub={<span className="hidden sm:inline">ثلاث خطوات. لا يُحفظ شيء قبل الخطوة الأخيرة.</span>} />
        <div className="rounded-card bg-surface px-4 py-3 shadow-card max-sm:-mx-4 max-sm:-mt-9 max-sm:rounded-none max-sm:bg-transparent max-sm:shadow-none sm:px-6 sm:py-4"><Stepper steps={steps} /></div>

        {options.error && !options.data ? <ErrorState title="تعذّر تحميل الجامعات والخطوط" text="تأكد من اتصالك ثم حاول مرة أخرى." onRetry={() => void options.reload()} card />
          : step > 0 && !options.data ? <SkeletonForm rows={2} />
            : step === 0 ? (
              <>
                <FormSection title="بيانات الطالب" help="اكتب الاسم كما في بطاقته. يدخل الطالب التطبيق برقم هاتفه.">
                  <TextField id="add-fullName" label="الاسم بالكامل" value={d.fullName} autoComplete="off" onChange={(e) => set({ fullName: e.target.value })}
                    error={errors.fullName} help="ثلاثة أسماء على الأقل." />
                  <FieldRow>
                    <TextField id="add-phone" label="رقم الهاتف" type="tel" inputMode="tel" ltr autoComplete="off" placeholder="01xxxxxxxxx" value={d.phone}
                      onChange={(e) => set({ phone: e.target.value })} error={errors.phone} help="رقم واحد لكل طالب." />
                    <SelectField id="add-universityId" label="الجامعة" value={d.universityId} placeholder={options.data ? 'اختر الجامعة' : 'جارٍ تحميل الجامعات…'}
                      options={universities.map((u) => ({ value: u.id, label: u.name }))} onChange={(e) => set({ universityId: e.target.value, lineId: '' })}
                      error={errors.universityId} help="تحدد الخطوط والرحلات التي تظهر في الخطوة التالية." />
                  </FieldRow>
                </FormSection>
                <FormSection title="كلمة مرور التطبيق" help="تكتبها أنت الآن وتعطيها للطالب. لا تظهر بعد التسجيل.">
                  <div className="sm:max-w-[calc(50%-8px)]">
                    <PasswordField id="add-password" label="كلمة المرور" autoComplete="new-password" value={d.password} onChange={(e) => set({ password: e.target.value })}
                      error={errors.password} help="8 أحرف على الأقل. اضغط العين لتقرأها له." />
                  </div>
                </FormSection>
              </>
            ) : step === 1 ? (
              <>
                <FormSection title="من أين يركب؟" help={`تظهر الخطوط التي لها رحلة إلى ${university?.name ?? 'جامعته'} فقط.`}>
                  {serving.length === 0 ? (
                    <Note tone="warning" title={`لا خط يذهب إلى ${university?.name ?? 'هذه الجامعة'}`}
                      action={<Button sm kind="tonal" to={`${back.replace(/\/students$/, '')}/lines`}>افتح الخطوط</Button>}>
                      أضف رحلة إلى هذه الجامعة من صفحة «الخطوط»، أو ارجع واختر جامعة أخرى.
                    </Note>
                  ) : (
                    <FieldRow>
                      <SelectField label="الخط" value={d.lineId} options={serving.map((l) => ({ value: l.id, label: l.name }))} onChange={(e) => pickLine(e.target.value)} />
                      <SelectField label="المحطة" value={d.stationId} options={stations.map((s) => ({ value: s.id, label: s.name }))} onChange={(e) => pickStation(e.target.value)} help="محطات الخط بترتيب المسار." />
                    </FieldRow>
                  )}
                </FormSection>
                {serving.length > 0 && (
                  <FormSection title="في أي رحلة؟" help="الوقت هو وقت مرور الباص على محطته. يستطيع الطالب تغيير رحلته لاحقاً من التطبيق.">
                    {departures.length === 0 ? (
                      <Note tone="warning" title="لا رحلة ذهاب تمر على هذه المحطة"
                        action={<Button sm kind="tonal" to={`${back.replace(/\/students$/, '')}/lines`} className="!bg-surface">افتح الخطوط</Button>}>
                        اختر محطة أخرى، أو أضف وقت المحطة إلى رحلة من صفحة «الخطوط».
                      </Note>
                    ) : (
                      <>
                        <RadioCards label="رحلة الذهاب" cols={3} value={d.departureTripId} onChange={(v) => set({ departureTripId: v })}
                          options={departures.map((o) => ({ value: o.trip.id, label: tripLabel(o) }))} />
                        {returns.length > 0
                          ? <RadioCards label="رحلة العودة" cols={3} value={d.returnTripId} onChange={(v) => set({ returnTripId: v })}
                            options={returns.map((o) => ({ value: o.trip.id, label: tripLabel(o) }))} />
                          : <p className="m-0 text-label text-ink-2">لا رحلة عودة إلى هذا الخط من جامعته؛ يُسجَّل ذهاباً فقط.</p>}
                      </>
                    )}
                  </FormSection>
                )}
              </>
            ) : (
              <>
                <FormSection title="أول اشتراك له" help="الأسعار هي أسعار الخط الذي اخترته. ما لا تبيعه الشركة الآن يظهر مقفلاً.">
                  <RadioCards<SubType> label="نوع الاشتراك" cols={3} value={d.type} onChange={(type) => set({ type })}
                    options={[
                      { value: 'termly', label: 'فصل دراسي' },
                      { value: 'yearly', label: 'الفصلان معاً', sub: yearlyOn ? undefined : 'غير متاح الآن', disabled: !yearlyOn },
                      { value: 'daily', label: 'يومي', sub: dailyOn ? `${moneyText(line?.price_daily)} نقداً في الباص` : lineDaily ? 'غير مفعّل' : 'لا يُباع على هذا الخط', disabled: !dailyOn },
                    ]} />
                  {d.type !== 'daily' && (periodsQuery.loading ? <SkeletonForm rows={1} /> : periodsForType.length === 0
                    ? <Note tone="warning" title="لا فترة متاحة للدفع الآن لهذا النوع">افتح الفترة من صفحة «مواعيد الاشتراك»، أو اختر نوعاً آخر.</Note>
                    : <RadioCards label="فترة الاشتراك" cols={2} value={d.periodKey} onChange={(periodKey) => set({ periodKey })}
                      options={periodsForType.map((p) => ({ value: periodKey(p), label: p.label,
                        sub: <span>{priceOf(p.period_code) != null ? <Money value={priceOf(p.period_code)} /> : 'بدون سعر'}{p.phase === 'upcoming' ? ' · دفع مقدم' : ''}</span> }))} />)}
                </FormSection>
                <FormSection title="راجع قبل التسجيل" help="لا يُحفظ شيء قبل أن تضغط «تسجيل الطالب».">
                  <InfoRows labelW={110} rows={[
                    ['الطالب', <span key="s" className="flex flex-col"><span className="font-semibold">{d.fullName.trim()}</span><span className="text-label text-ink-2"><Ltr>{phoneText(phoneDigits(d.phone))}</Ltr> · {university?.name}</span></span>],
                    ['الخط والمحطة', `${line?.name ?? '—'} · ${station?.name ?? '—'}`],
                    ['الرحلات', tripsLine || '—'],
                    ['الاشتراك', <span key="p">{d.type === 'daily' ? 'يومي' : period?.label ?? '—'} · <Money value={price} /></span>],
                  ]} />
                  <Note tone="teal" title="يُسجَّل اشتراكه «بانتظار الدفع»">يدفع من التطبيق ويرسل إيصالاً تراجعه، أو يدفع لك نقداً فتفعّله من صفحته.</Note>
                </FormSection>
              </>
            )}

        <div className="hidden items-center gap-2 sm:flex">{nav(false)}</div>
        <PhoneBar><div className="flex gap-2">{nav(true)}</div></PhoneBar>
      </div>

      <Dialog open={leaving} onClose={() => setLeaving(false)} icon="alert" tone="warning" title="الخروج بدون تسجيل الطالب؟"
        actions={[<Button key="c" kind="secondary" onClick={() => setLeaving(false)}>أكمل التسجيل</Button>, <Button key="o" kind="danger" onClick={onLeave}>خروج بدون تسجيل</Button>]}>
        <p className="m-0">لم يُحفظ شيء بعد. ما كتبته في الخطوات الثلاث سيُمسح.</p>
      </Dialog>

      <Dialog open={outcome?.kind === 'created'} onClose={() => onOpenStudent(outcome?.kind === 'created' ? outcome.id : '')} icon="check" tone="success"
        title={outcome?.kind === 'created' ? `سُجّل ${shortName(outcome.draft.fullName)} في شركتك` : ''}
        actions={[<Button key="a" kind="secondary" onClick={restart}>إضافة طالب آخر</Button>,
          <Button key="o" onClick={() => onOpenStudent(outcome?.kind === 'created' ? outcome.id : '')}>افتح صفحة الطالب</Button>]}>
        {outcome?.kind === 'created' && (
          <>
            <p className="m-0">اشتراكه في {outcome.period} على خط {outcome.line} «بانتظار الدفع».</p>
            <div className="flex flex-col gap-2 rounded-inner bg-ground px-4 py-3 text-ink">
              <div className="text-label text-ink-2">أبلغه الآن. يدخل التطبيق بـ:</div>
              <div className="flex items-center gap-3 text-small"><span className="w-24 flex-none text-label text-ink-3">رقم الهاتف</span><Ltr className="font-semibold">{phoneText(phoneDigits(outcome.draft.phone))}</Ltr></div>
              <div className="flex items-center gap-3 text-small"><span className="w-24 flex-none text-label text-ink-3">كلمة المرور</span><Ltr className="flex-1 font-semibold">{outcome.draft.password}</Ltr>
                <Button sm kind="outline" icon={copied ? 'check' : 'copy'} onClick={() => { void navigator.clipboard?.writeText(outcome.draft.password).then(() => setCopied(true), () => undefined); }}>{copied ? 'نُسخت' : 'نسخ'}</Button></div>
            </div>
            <p className="m-0 flex items-center gap-1.5 text-label"><Icon name="info" size={14} />لن تظهر كلمة المرور مرة أخرى بعد إغلاق هذه النافذة.</p>
          </>
        )}
      </Dialog>

      <Dialog open={outcome?.kind === 'invited'} onClose={onLeave} icon="mail" tone="teal" title="لهذا الرقم حساب في باصك، فأرسلنا له دعوة"
        actions={[<Button key="a" kind="secondary" onClick={onLeave}>تم</Button>, <Button key="o" onClick={onShowInvites}>عرض الدعوات</Button>]}>
        {outcome?.kind === 'invited' && (
          <>
            <p className="m-0"><b className="font-semibold text-ink">لم يُضف الطالب بعد.</b> صاحب الرقم <Ltr>{phoneText(outcome.phone)}</Ltr> يرى الدعوة في التطبيق ويوافق بحسابه وكلمة مروره الحاليين، ثم يظهر في قائمتك.</p>
            <p className="m-0">كلمة المرور التي كتبتها لم تُستعمل. تنتهي الدعوة بعد 14 يوماً، وتتابعها في تبويب «الدعوات».</p>
          </>
        )}
      </Dialog>
    </Page>
  );
};
