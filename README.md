# باصك (Basak) - University Bus Subscription System 🚌

نظام شامل ومتكامل لإدارة اشتراكات باصات الجامعات، يتكون من 3 أسطح رئيسية مدعومة ببنية سحابية قوية على **Supabase**:
1. **تطبيق الموبايل (Flutter)**: للطلاب ومشرفي الباصات، بنظام تصميم زجاجي فاخر **iOS-Style Glassmorphism (White & Baby Blue)**.
2. **لوحة تحكم الإدارة (Admin Web Dashboard)**: مبنية بـ **React + Vite + Tailwind CSS** وخطوط **Inter & Cairo**.
3. **الواجهة الخلفية وقاعدة البيانات (Supabase Backend)**: Postgres + RLS + Storage للإيصالات + Realtime للشات + Edge Functions لإعادة التعيين اليومي.

---

## المميزات وقواعد العمل الصارمة (Business Logic)
1. **رقم هاتف الطالب فريد تماماً** على مستوى الـ Database لمنع أي تكرار.
2. **رمز QR تعريفي ثابت** لكل طالب مخصص للاستعلام فقط للمشرف ولا يسجل الحضور.
3. **مفتاح "نازل بكرة" اليومي**: هو المصدر الوحيد لتأكيد الحضور، ويقفل تلقائياً الساعة 1:00 ظهراً يومياً.
4. **اشتراك واحد نشط فقط** لكل طالب في أي وقت (فصلي / سنوي / يومي كاش).
5. **مراجعة الإيصالات البنكية**: اعتماد فوري، أو رفض مع **إلزامية كتابة سبب الرفض** وإمكانية إعادة الرفع حتى 4 مرات إضافية (5 محاولات إجمالاً).
6. **لا يمكن تعديل البروفايل داخلياً**: لتغيير الخط أو المحطة يجب حذف الحساب وإعادة التسجيل.
7. **حسابات المشرفين والأدمن**: يتم إنشاؤها عبر الإدارة حصراً ولا يوجد تسجيل ذاتي للمشرفين.

---

## هيكل المشروع (Project Structure)
```
باصك (Basak)/
├── mobile_app/           # تطبيق الفلاتر (للطلاب والمشرفين)
│   ├── lib/
│   │   ├── core/         # GlassContainer, FloatingGlassNavBar, GlassScaffold, Theme
│   │   └── features/     # Auth, Student (Lines, Subs, QR, Chat), Supervisor (Counts, Scan, Review)
│   └── pubspec.yaml
├── admin_web/            # لوحة تحكم الأدمن (React + Vite + Tailwind)
│   ├── src/
│   │   ├── components/   # Sidebar, Topbar, StatsRow, WeeklyChart, TopLines, ReceiptsTable
│   │   └── pages/        # Overview, Companies, Lines, Supervisors, Reports
│   └── package.json
└── supabase/             # قاعدة البيانات والخادم
    ├── migrations/       # كل تغييرات قاعدة البيانات بالترتيب (المصدر الوحيد للـ SQL)
    ├── functions/        # Edge Functions (إنشاء/حذف الطلاب والمشرفين ومديري الشركات...)
    └── tests/            # اختبارات الصلاحيات والتدفق الكامل
```

---

## تشغيل المشروع محلياً

### 1. إعداد قاعدة البيانات (Supabase)
طبّق ملفات `supabase/migrations/` بالترتيب الزمني (حسب اسم الملف) على مشروع Supabase، ثم انشر الـ Edge Functions:
```powershell
npx.cmd supabase@latest login
powershell -File supabase/deploy-functions.ps1
```

### 2. تشغيل لوحة الأدمن (Admin Web)
```bash
cd admin_web
npm install
npm run dev
```
تفتح اللوحة مباشرة على `http://localhost:5173`.

### 3. تشغيل تطبيق الموبايل (Mobile App)
```bash
cd mobile_app
flutter pub get
flutter run
```

---

## تحديث 2026-10-04: خطوات النشر (بالترتيب)

1. **قاعدة البيانات** — شغّل في SQL Editor بالترتيب:
   `supabase/migrations/20261004000001_supervisor_lines_and_permissions.sql`،
   `20261004000002_academic_terms_and_subscription_periods.sql`،
   `20261004000003_student_password_reset.sql` (آمنة لإعادة التشغيل).
2. **Edge Functions** — أعد نشر كل الوظائف (تغيّر `_shared/admin-auth.ts`) مع الوظيفة الجديدة
   `student-reset-password`: `supabase/deploy-functions.ps1`.
3. **لوحة التحكم (Vercel)** — أعد النشر من مجلد `admin_web` (Root Directory = `admin_web`).
   رسالة `MIME type ('text/html')` وخطأ `400` عند إضافة مشرف كانا من نسخة قديمة من اللوحة ما زالت
   تُرسل عمود `password` المحذوف؛ `vercel.json` الجديد يمنع تخزين `index.html` ولا يعيد توجيه `/assets/*`.
4. **تطبيق Android** — ابنِ الإصدار `1.0.5+6` (يحتاجه المشرفون والطلاب).

## تحديث 2026-10-07: مواعيد التصويت وتذكير الطلاب (بالترتيب)

1. **قاعدة البيانات** — شغّل في SQL Editor بالترتيب:
   `supabase/migrations/20261020000000_company_access_never_null.sql` (إصلاح أمني عاجل: كان أي حساب
   مسجّل يقدر يعدّل خطوط وإعدادات شركة غيره)، ثم `20261020000001_vote_window_settings.sql`.
   القيم الافتراضية تُبقي التصويت من ٤ م حتى ٦ ص بدون تذكير، فلا يتغير شيء حتى يعدّلها الأدمن.
2. **لوحة التحكم (Vercel)** — أعد النشر. المواعيد في «الإعدادات الافتراضية» (مدير النظام، لكل الشركات)
   و«إعدادات الشركة» (مواعيد خاصة بالشركة، أو الرجوع لإعداد المنصة).
3. **تطبيق Android** — ابنِ الإصدار `1.0.3+15`: يقرأ المواعيد من الإعدادات بدل ٤ م / ٦ ص الثابتة،
   ويجدول على الموبايل تذكيراً لمن لم يؤكد رحلته (يتوقف بمجرد التأكيد أو الاعتذار). التطبيق القديم
   يظل يعمل لكنه يعرض المواعيد الثابتة، والسيرفر هو الذي يقرر فتح التصويت وقفله.

اختبارات محلية كاملة (SQL + HTTP عبر GoTrue/PostgREST/Edge Functions): `supabase/tests/local/README.md`.
