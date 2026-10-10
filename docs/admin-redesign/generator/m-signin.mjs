/** Sign-in, password reset, blocked accounts, and the global pieces no page owns. */
import {
  board, shellDesktop, shellPhone, dialog, scrim, field, btn, note, toast, emptyState, skeleton, attentionList, sectionHead,
  ico, C, T, R, CARD, FONT, SHADOW,
} from './kit.mjs';
import { frame, mini, FW } from './m-common.mjs';

const ROW = 'J';
const logo = (s = 44) => `<span aria-hidden="true" style="width:${s}px;height:${s}px;border-radius:${Math.round(s / 3.6)}px;background:${C.ink};color:#FFFFFF;display:flex;align-items:center;justify-content:center;flex:none">${ico('bus', Math.round(s / 2), 1.75)}</span>`;
const brandRow = (o = {}) => `<div style="display:flex;align-items:center;gap:12px">${o.onInk ? `<span aria-hidden="true" style="width:44px;height:44px;border-radius:12px;background:#FFFFFF;color:${C.ink};display:flex;align-items:center;justify-content:center">${ico('bus', 22)}</span>` : logo()}<div><div style="font-size:20px;line-height:26px;font-weight:600;color:${o.onInk ? '#FFFFFF' : C.ink}">باصك</div><div style="${T.label};color:${o.onInk ? '#C9D8E1' : C.ink3}">لوحة شركات النقل</div></div></div>`;

/* ── Forms ──────────────────────────────────────────────────────── */
const F = {
  signin: (o = {}) => ({ title: 'تسجيل الدخول', sub: 'ادخل ببريدك الإلكتروني وكلمة المرور التي اخترتها.',
    top: o.top, body: `${field({ label: 'البريد الإلكتروني', value: o.email ?? '', placeholder: 'name@example.com', ltr: true, phone: o.phone, state: o.focus ? 'focus' : undefined })}
${field({ type: 'password', label: 'كلمة المرور', value: o.pw, placeholder: 'كلمة المرور', phone: o.phone, error: o.pwErr })}
<div style="display:flex;margin-top:-4px">${btn('نسيت كلمة المرور؟', { kind: 'link', sm: true, extra: o.phone ? 'height:44px;' : '' })}</div>`,
    primary: btn('دخول', { phone: o.phone, full: true, state: o.loading ? 'loading' : undefined, extra: 'height:48px;font-size:15px;' }),
    foot: 'للمديرين فقط. الطلاب والمشرفون يدخلون من تطبيق باصك برقم الهاتف.' }),
  forgot: (o = {}) => ({ title: 'استعادة كلمة المرور', sub: 'اكتب بريدك الإلكتروني، ونرسل إليه رابطاً تختار منه كلمة مرور جديدة.', back: true,
    top: o.sent ? note({ tone: 'success', title: 'إن كان البريد مسجلاً فقد أرسلنا الرابط', text: 'افتح بريدك واضغط الرابط. إن لم تجده فانظر في البريد غير المرغوب، ثم أعد المحاولة بعد دقيقة.' }) : o.top,
    body: field({ label: 'البريد الإلكتروني', value: o.email ?? '', placeholder: 'name@example.com', ltr: true, phone: o.phone, error: o.err }),
    primary: btn(o.sent ? 'أرسل الرابط مرة أخرى' : 'أرسل رابط الاستعادة', { kind: o.sent ? 'secondary' : 'primary', phone: o.phone, full: true, extra: 'height:48px;font-size:15px;' }) }),
  newpw: (o = {}) => ({ title: o.invite ? 'اختر كلمة مرور لحسابك' : 'كلمة مرور جديدة', sub: o.invite ? 'أهلاً بك في باصك. اختر كلمة مرور تدخل بها إلى لوحة شركتك.' : 'اختر كلمة مرور جديدة لحسابك، ثم تدخل مباشرة.',
    top: o.top, body: `${field({ type: 'password', label: 'كلمة المرور الجديدة', value: o.empty ? undefined : 'x', placeholder: '8 أحرف على الأقل', help: '8 أحرف أو أكثر.', phone: o.phone, error: o.e1 })}
${field({ type: 'password', label: 'أعد كتابتها', value: o.empty ? undefined : 'x', placeholder: 'أعد كتابة كلمة المرور', phone: o.phone, error: o.e2 })}`,
    primary: btn('حفظ كلمة المرور والدخول', { phone: o.phone, full: true, state: o.dead ? 'disabled' : undefined, extra: 'height:48px;font-size:15px;' }),
    after: o.dead ? btn('اطلب رابطاً جديداً', { kind: 'secondary', phone: o.phone, full: true }) : '' }),
};
const formCol = (f, o = {}) => `<div style="display:flex;flex-direction:column;gap:${o.phone ? 20 : 24}px;width:100%;max-width:400px">
${f.back ? `<a href="#" style="display:inline-flex;align-items:center;gap:6px;font-size:13px;line-height:20px;font-weight:500;color:${C.teal};align-self:flex-start;min-height:${o.phone ? 44 : 24}px">${ico('arrowBack', 14, 2)}<span>رجوع إلى تسجيل الدخول</span></a>` : ''}
<div><h1 style="margin:0;${o.phone ? T.pagePhone : T.page}">${f.title}</h1><p style="margin:4px 0 0;${T.small};color:${C.ink2}">${f.sub}</p></div>
${f.top ?? ''}
<form style="display:flex;flex-direction:column;gap:16px">${f.body}</form>
<div style="display:flex;flex-direction:column;gap:8px">${f.primary}${f.after ?? ''}</div>
${f.foot ? `<p style="margin:0;${T.label};color:${C.ink3};display:flex;gap:8px;align-items:flex-start"><span style="display:flex;padding-top:2px">${ico('lock', 14, 2)}</span><span>${f.foot}</span></p>` : ''}
</div>`;
const POINTS = [['receipt', 'راجع إيصالات الدفع واقبلها في دقيقة'], ['users', 'اعرف كم راكباً في كل رحلة غداً'], ['megaphone', 'أخبر طلابك بأي تغيير في لحظته']];
const side = `<div style="flex:1;min-width:0;background:${C.ink};color:#FFFFFF;display:flex;flex-direction:column;justify-content:space-between;padding:56px 64px">
${brandRow({ onInk: true })}
<div style="display:flex;flex-direction:column;gap:28px;max-width:520px"><h2 style="margin:0;font-size:34px;line-height:46px;font-weight:600">كل ما يخص باصات شركتك وطلابها، في مكان واحد.</h2>
<ul style="margin:0;padding:0;list-style:none;display:flex;flex-direction:column;gap:16px">${POINTS.map(([i, t]) => `<li style="display:flex;align-items:center;gap:14px;font-size:16px;line-height:24px;color:#E3EDF2"><span style="width:40px;height:40px;border-radius:${R.control}px;background:rgba(255,255,255,.1);display:flex;align-items:center;justify-content:center;flex:none">${ico(i, 20)}</span>${t}</li>`).join('')}</ul></div>
<div style="${T.label};color:#9FB6C3">تعمل من الهاتف والكمبيوتر، من المتصفح مباشرة.</div>
</div>`;
/** Desktop: the form column on the start side (560), the calm ink panel beside it. */
const authDesktop = (size, f) => `<div data-root dir="rtl" style="${size};background:${C.surface};${FONT};color:${C.ink};display:flex;overflow:hidden">
<div style="width:560px;flex:none;display:flex;flex-direction:column;padding:40px 80px"><div style="flex:none">${brandRow()}</div><div style="flex:1;display:flex;align-items:center">${formCol(f)}</div><div style="${T.cap};color:${C.ink3}">© باصك 2026</div></div>
${side}
</div>`;
const authPhone = (size, f) => `<div data-root dir="rtl" style="${size};background:${C.surface};${FONT};color:${C.ink};display:flex;flex-direction:column;padding:24px 16px 24px;gap:32px;overflow:hidden">
${brandRow()}
${formCol(f, { phone: true })}
</div>`;
/** A full page without the dashboard: the account cannot use it. */
const notice = (size, { icon, tone, title, text, action, phone }) => `<div data-root dir="rtl" style="${size};background:${C.ground};${FONT};color:${C.ink};display:flex;flex-direction:column;align-items:center;${phone ? 'padding:24px 16px;gap:32px' : 'padding:48px;gap:48px'};overflow:hidden">
<div style="align-self:${phone ? 'flex-start' : 'center'}">${brandRow()}</div>
<div style="${CARD};width:100%;max-width:520px;padding:${phone ? '28px 20px' : '40px'};display:flex;flex-direction:column;align-items:center;text-align:center;gap:8px"><span aria-hidden="true" style="width:56px;height:56px;border-radius:28px;background:${tone === 'danger' ? C.badBg : C.warnBg};color:${tone === 'danger' ? C.bad : C.warn};display:flex;align-items:center;justify-content:center;margin-bottom:8px">${ico(icon, 26)}</span><h1 style="margin:0;${phone ? T.section : 'font-size:22px;line-height:30px;font-weight:600'}">${title}</h1><p style="margin:0;${T.small};color:${C.ink2}">${text}</p><div style="margin-top:16px;display:flex;gap:8px;${phone ? 'flex-direction:column;align-self:stretch' : ''}">${action}</div></div>
</div>`;

board('AdmSignIn', { row: ROW, w: 1440, h: 900, title: 'Admin web · Sign-in · Desktop', tab: 'باصك · تسجيل الدخول',
  body: (size) => authDesktop(size, F.signin({ email: 'ahmed@elnawras-bus.example', focus: true })) });
board('AdmSignInNewPassword', { row: ROW, w: 1440, h: 900, title: 'Admin web · Sign-in · New password (from the e-mailed link; the invitation uses the same page) · Desktop', tab: 'باصك · كلمة مرور جديدة',
  body: (size) => authDesktop(size, F.newpw({ e2: 'الكلمتان غير متطابقتين. أعد كتابة الثانية.' })) });

/* ── Every message of the door, as cards ────────────────────────── */
const cardFrame = (label, text, f) => `<section style="display:flex;flex-direction:column;gap:10px;min-width:0"><div dir="ltr"><h3 style="margin:0;font-size:16px;line-height:24px;font-weight:600">${label}</h3><p style="margin:0;font-size:13px;line-height:20px;color:${C.ink2};min-height:60px">${text}</p></div><div dir="rtl" style="border-radius:${R.inner}px;box-shadow:0 0 0 1px ${C.hair}, ${SHADOW.floating};background:${C.surface};padding:28px 24px;display:flex;justify-content:center;flex:1">${formCol(f)}</div></section>`;
const bad = (title, text) => note({ tone: 'danger', title, text });
board('AdmSignInStates', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Sign-in · Every message of the door', tab: 'Basak admin web · Sign-in states',
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:32px">
<div dir="ltr"><h2 style="margin:0;font-size:20px;line-height:28px;font-weight:600">The form column in each state</h2><p style="margin:0;font-size:14px;line-height:22px;color:${C.ink2}">Same column as on the sign-in page (desktop and phone). Messages sit above the fields they are about; never the server's text.</p></div>
<div style="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:40px 32px;align-items:stretch">
${cardFrame('Wrong e-mail or password', 'One sentence for both, so nobody learns which e-mails exist. The password field is cleared and marked.', F.signin({ email: 'ahmed@elnawras-bus.example', pwErr: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.' }))}
${cardFrame('Signing in', 'The button shows it is working and cannot be pressed twice.', F.signin({ email: 'ahmed@elnawras-bus.example', pw: 'x', loading: true }))}
${cardFrame('Not a manager account', 'A student, a supervisor, or an account that is no longer attached to any company: signed out again and told where to go.', F.signin({ email: 'student2031@mail.example', top: bad('هذا الحساب ليس حساب مدير', 'لوحة الشركات لمديري شركات النقل فقط. إن كنت طالباً أو مشرفاً فادخل من تطبيق باصك.') }))}
${cardFrame('No connection', 'The request never reached the server.', F.signin({ email: 'ahmed@elnawras-bus.example', pw: 'x', top: bad('تعذّر الاتصال', 'تأكد من اتصالك بالإنترنت ثم اضغط «دخول» مرة أخرى.') }))}
${cardFrame('Session expired', 'Shown on the sign-in page after an expired session sent the manager back here; the page they were on reopens after signing in.', F.signin({ email: 'ahmed@elnawras-bus.example', top: note({ tone: 'warning', title: 'انتهت جلستك', text: 'للأمان نطلب الدخول من جديد بعد مدة. ادخل لتعود إلى حيث كنت.' }) }))}
${cardFrame('E-mail not confirmed', 'The account exists but its e-mail was never confirmed.', F.signin({ email: 'karim@alsafwa.example', top: note({ tone: 'warning', title: 'أكّد بريدك الإلكتروني أولاً', text: 'أرسلنا إليك رسالة عند إنشاء الحساب. افتحها واضغط الرابط، ثم ادخل.' }) }))}
${cardFrame('Forgot password · step 1', 'Its own small page instead of today\'s link that silently reuses the e-mail field.', F.forgot({ email: 'ahmed@elnawras-bus.example' }))}
${cardFrame('Forgot password · link sent', 'The same answer whether or not the e-mail is registered.', F.forgot({ email: 'ahmed@elnawras-bus.example', sent: true }))}
${cardFrame('Reset link expired', 'The link was opened too late or used before: the fields are held back and the way out is one press.', F.newpw({ empty: true, dead: true, top: bad('انتهت صلاحية الرابط', 'رابط الاستعادة يعمل مرة واحدة ولمدة قصيرة. اطلب رابطاً جديداً.') }))}
</div>
</div>` });

/* ── Blocked at the door ────────────────────────────────────────── */
const out = (phone) => btn('تسجيل الخروج', { kind: 'secondary', icon: 'logout', phone, full: phone });
const suspended = (phone) => ({ phone, icon: 'power', tone: 'warning', title: 'حساب شركة «النورس للنقل» موقوف حالياً', text: 'لا يمكن استخدام لوحة الشركة حتى تعيد إدارة المنصة تشغيل الشركة. بياناتكم محفوظة كما هي: الطلاب والخطوط والإيصالات.', action: out(phone) });
const missing = (phone) => ({ phone, icon: 'building', tone: 'danger', title: 'لم نجد شركة لهذا الحساب', text: 'حسابك غير مرتبط بشركة نقل الآن، أو أن الشركة أُزيلت. تواصل مع إدارة المنصة لتربط حسابك من جديد.', action: btn('إعادة المحاولة', { kind: 'secondary', icon: 'refresh', phone, full: phone }) + out(phone) });
const dummyBody = `<div style="display:grid;grid-template-columns:minmax(0,7fr) minmax(0,5fr);gap:24px">${skeleton('list', { rows: 3 })}<div style="display:flex;flex-direction:column;gap:16px">${skeleton('stat')}${skeleton('stat')}</div></div>`;
const expiredDialog = (phone) => dialog({ phone, icon: 'lock', tone: 'warning', title: 'انتهت جلستك',
  body: '<span>للأمان نطلب الدخول من جديد بعد مدة. ما كتبته في هذه الصفحة ولم تحفظه لن يُحفظ؛ ادخل ثم أعد المحاولة.</span>',
  actions: ['', btn('تسجيل الدخول من جديد', { phone, full: phone })] });
board('AdmSignInBlocked', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Sign-in · Stopped company, account without a company, session expired', tab: 'Basak admin web · Blocked states',
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">
${frame('Company suspended or archived', 'A company admin of a stopped company gets no dashboard at all: one calm page, what is safe, and the only action. The word follows the company state («موقوف» / «مؤرشف»).', notice(`width:${FW}px;height:560px`, suspended()))}
${frame('Account without a company', 'The company row is missing or could not be read.', notice(`width:${FW}px;height:560px`, missing()))}
${frame('Session expired while working', 'Today only edge-function calls say it, as an inline error. Here any refused request opens one dialog; the page stays behind it.', shellDesktop({ size: `width:${FW}px;height:560px`, active: 'today', title: 'اليوم', sub: 'السبت 10 أكتوبر 2026', body: dummyBody, overlay: scrim(expiredDialog()) }))}
</div>` });

/* ── Global pieces ──────────────────────────────────────────────── */
const toastStack = (inner, phone) => `<div aria-live="polite" style="position:absolute;${phone ? 'inset-inline:16px;bottom:16px' : 'inset-inline-start:288px;bottom:24px'};display:flex;flex-direction:column;gap:8px;z-index:8">${inner}</div>`;
const T_NEW = { tone: 'info', text: 'إيصال دفع جديد من يوسف أحمد عبد الفتاح · خط الزرقا', action: 'راجعه' };
const T_OK = { tone: 'success', text: 'قُبل إيصال منة الله إبراهيم. اشتراكها نشط الآن.', action: 'تراجع' };
const T_BAD = { tone: 'danger', text: 'لم يُحفظ التغيير. تأكد من اتصالك ثم حاول مرة أخرى.', action: 'حاول مرة أخرى' };
const todayLite = `<section style="display:flex;flex-direction:column;gap:12px">${sectionHead('يحتاج منك الآن')}${attentionList([{ count: 8, tone: 'warning', title: '8 إيصالات تنتظر مراجعتك', sub: 'أحدثها وصل الآن', action: 'راجع الإيصالات', primary: true }, { count: 2, tone: 'teal', title: 'طالبان نسيا كلمة المرور', sub: 'أعطِ كل طالب رمزاً مؤقتاً يدخل به', action: 'افتح الطلبات' }])}</section>`;
const denied = (phone) => emptyState({ card: true, phone, icon: 'lock', title: 'هذه الصفحة ليست ضمن صلاحياتك', text: 'يفتحها مدير المنصة فقط. إن كنت تحتاج شيئاً منها فاطلبه من إدارة المنصة.', action: btn('العودة إلى «اليوم»', { kind: 'secondary', icon: 'home', phone, full: phone }) });
const lost = (phone) => emptyState({ card: true, phone, icon: 'search', title: 'لا توجد صفحة بهذا العنوان', text: 'ربما تغيّر الرابط أو كُتب خطأ. كل الصفحات في القائمة.', action: btn('العودة إلى «اليوم»', { kind: 'secondary', icon: 'home', phone, full: phone }) });
board('AdmSignInGlobal', { row: ROW, w: 1440, lang: 'en', title: 'Admin web · Global pieces · Toasts, offline bar, no permission, 404', tab: 'Basak admin web · Global pieces',
  body: (size) => `<div data-root style="${size};background:#FFFFFF;${FONT};color:${C.ink};padding:64px;display:flex;flex-direction:column;gap:48px">
${frame('Toasts', 'Bottom start corner of the content, newest lowest, at most three. Live arrival (a new receipt: the badge in the menu grows at the same moment) with the action that opens it; a success with «تراجع» where the action can be undone; a failure that stays until dismissed and never shows the server text.', mini(520, { active: 'today', title: 'اليوم', sub: 'السبت 10 أكتوبر 2026', badges: { receipts: 8, requests: 2 }, body: todayLite, overlay: toastStack(toast({ ...T_BAD, w: 480 }) + toast({ ...T_OK, w: 480 }) + toast({ ...T_NEW, w: 480 })) }))}
${frame('Offline bar', 'Under the top bar on every page while there is no connection; buttons that write are held back, the last loaded data stays readable.', mini(420, { active: 'today', title: 'اليوم', sub: 'السبت 10 أكتوبر 2026', offline: true, actions: btn('إرسال إشعار للطلاب', { kind: 'outline', icon: 'megaphone', state: 'disabled' }), body: todayLite }))}
${frame('No permission', 'A company admin opening a platform address, or another company: inside the shell, so the menu still works. (Today this is a silent redirect.)', mini(520, { active: '', breadcrumb: ['النورس للنقل', 'غير مسموح'], body: denied() }))}
${frame('Page not found', 'An address that matches nothing. (Today this is a silent redirect to the first page.)', mini(520, { active: '', breadcrumb: ['النورس للنقل', 'صفحة غير موجودة'], body: lost() }))}
</div>` });

/* ── Phone ──────────────────────────────────────────────────────── */
board('AdmSignInPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Sign-in · Phone', tab: 'باصك · تسجيل الدخول · هاتف',
  body: (size) => authPhone(size, F.signin({ phone: true })) });
board('AdmSignInErrorPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Sign-in · Wrong password · Phone', tab: 'باصك · تسجيل الدخول · خطأ · هاتف',
  body: (size) => authPhone(size, F.signin({ phone: true, email: 'ahmed@elnawras-bus.example', pwErr: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.' })) });
board('AdmSignInForgotPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Sign-in · Forgot password, link sent · Phone', tab: 'باصك · استعادة كلمة المرور · هاتف',
  body: (size) => authPhone(size, F.forgot({ phone: true, email: 'ahmed@elnawras-bus.example', sent: true })) });
board('AdmSignInNewPasswordPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Sign-in · New password · Phone', tab: 'باصك · كلمة مرور جديدة · هاتف',
  body: (size) => authPhone(size, F.newpw({ phone: true, e1: 'قصيرة. اكتب 8 أحرف على الأقل.' })) });
board('AdmSignInSuspendedPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Sign-in · Company suspended · Phone', tab: 'باصك · شركة موقوفة · هاتف',
  body: (size) => notice(size, suspended(true)) });
board('AdmSignInToastPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Global pieces · Offline bar and toasts · Phone', tab: 'باصك · إشعارات الصفحة · هاتف',
  body: (size) => shellPhone({ size, active: 'today', offline: true, body: `<section style="display:flex;flex-direction:column;gap:10px">${sectionHead('يحتاج منك الآن', { phone: true })}${attentionList([{ count: 8, tone: 'warning', title: '8 إيصالات تنتظر مراجعتك', sub: 'أحدثها وصل قبل انقطاع الاتصال' }, { count: 2, tone: 'teal', title: 'طالبان نسيا كلمة المرور', sub: 'أعطِ كل طالب رمزاً مؤقتاً' }], { phone: true })}</section>`, overlay: toastStack(toast({ ...T_BAD, phone: true, text: 'لم يُحفظ التغيير. لا يوجد اتصال.' }) + toast({ tone: 'info', text: 'إيصال دفع جديد من يوسف أحمد', action: 'راجعه', phone: true }), true) }) });
board('AdmSignInLostPhone', { row: ROW, w: 390, h: 844, title: 'Admin web · Global pieces · No permission and 404 · Phone', tab: 'باصك · صفحة غير متاحة · هاتف',
  body: (size) => shellPhone({ size, active: '', title: 'باصك', body: `${denied(true)}${lost(true)}` }) });
void mini;
