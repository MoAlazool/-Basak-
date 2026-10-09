# Supabase Backend: باصك (Basak)

هذا المجلد يحتوي على كامل بنية قاعدة البيانات، سياسات الأمان (RLS)، مستودع التخزين (Storage Bucket)، والوظائف البرمجية الخاصة بنظام اشتراكات باصات الجامعة.

---

## ملفات الـ SQL Migrations بالترتيب:

1. **`migrations/20260926000001_initial_schema.sql`**:
   - جداول الشركات (`companies`)، المشرفين (`supervisors`)، الخطوط (`lines`)، المحطات (`stations`).
   - جدول الطلاب (`students`) مع قيد فريد صارم على رقم الهاتف (`phone UNIQUE`)، وتوليد كود QR فريد غير قابل للتعديل.
   - جدول الاشتراكات (`subscriptions`) مع فهرس فرعي يمنع وجود أكثر من اشتراك نشط أو معلق للطالب في نفس الوقت.
   - جدول الإيصالات (`receipts`) مع تحديد حد أقصى 5 محاولات وقيد إلزامي لكتابة سبب الرفض عند الرفض.
   - جدول الحالة اليومية للركوب (`daily_ride_status`) مع قيد فريد لكل طالب وتاريخ.
   - جدول الرسائل الفورية (`chat_messages`) والشكاوى (`complaints`).

2. **`migrations/20260926000002_rls_policies.sql`**:
   - تفعيل الـ Row Level Security على جميع الجداول.
   - دوال مساعدة للتحقق من الأدوار (`is_admin()`, `is_supervisor()`, `is_student()`).
   - سياسات صارمة: الطالب يرى ويعدل بياناته واشتراكاته وإيصالاته فقط، المشرف يرى خططه وإيصالات طلابه، والأدمن يملك صلاحية كاملة.

3. **`migrations/20260926000003_storage_setup.sql`**:
   - إنشاء Bucket خاص باسم `receipts` بحد أقصى 5 ميجابايت للصور وملفات PDF.
   - سياسات الأمان لرفع الإيصالات وعرضها بواسطة الطالب والمشرف المعين فقط.

4. **`migrations/20260926000004_daily_reset_logic.sql`**:
   - دالة `toggle_student_daily_ride` لتسجيل "نازل بكرة" مع التحقق من شرط الإغلاق الساعة 1:00 ظهراً ومنع التعديل بأثر رجعي.
   - دالة `reset_daily_rides_at_1pm` لإعادة التعيين التلقائي (أُزيلت في `20261007000003_security_review_fixes.sql`؛ نافذة التصويت ٤ م - ٦ ص تُفرض داخل `toggle_student_daily_ride`).
   - دالة `get_line_rider_counts` لحساب أعداد الركاب في المحطات اليوم وغداً بناءً على التبديل المباشر.
   - دالة `lookup_student_by_qr` للبحث عن الطالب بالـ QR دون تسجيل أي حضور.

5. **`migrations/20260926000005_receipt_triggers.sql`**:
   - Triggers للتحقق التلقائي من رقم المحاولة (1 إلى 5).
   - تفعيل الاشتراك تلقائياً عند اعتماد المشرف، أو تحويله إلى مرفوض مع التحقق من وجود سبب مكتوب.
   - منع أي تعديل على بيانات بروفايل الطالب الأساسية (الحذف وإعادة التسجيل فقط).

6. **`migrations/20260926000006_seed_data.sql`**:
   - بيانات أولية تجريبية للشركات والخطوط والمحطات والأسعار ومواعيد الذهاب والعودة.

---

## كيفية التطبيق على Supabase:
1. افتح مشروعك في [Supabase Dashboard](https://supabase.com/dashboard).
2. انتقل إلى **SQL Editor**.
3. قم بنسخ وتشغيل الملفات من `1` إلى `6` بالترتيب.

---

## Wallet cards (Apple Wallet / Google Wallet)

Each student can save their permanent QR as a wallet card. The card belongs to the
student (serial / object id = `students.id`, barcode = the bare `students.qr_code_value`)
and is branded by the transport company they ride with. Whether a student may ride is
still decided only by `supervisor_check_in_student()` at scan time.

**Pieces**

| What | Where |
|---|---|
| What a card shows (one rule for both wallets) | `wallet_card_content(student_id)` in `migrations/20261009000001_wallet_card_per_company.sql` |
| Company design, logo and contact | `wallet_card_settings` (per company) and `companies.logo_path / contact_phone / contact_label`, edited on the dashboard page "بطاقة المحفظة" |
| Issue a card | function `student-wallet-pass` |
| Apple's pass web service (register / what changed / latest pass) | function `wallet-apple-web` |
| Deliver changes to installed cards | function `wallet-sync` (woken by database triggers through `pg_net`, and by the dashboard for a company rollout) |
| Student photo for Google Wallet | function `wallet-photo` (unguessable link, small copy only) |

Line and pickup station appear only for an **approved** subscription (valid today, or
approved in advance). Nothing runs on a timer: a subscription that starts or ends by date
alone is picked up the next time the student is scanned or opens the QR screen.

**One-time setup**

1. Apple (paid Apple Developer account): create a *Pass Type ID*, create its certificate
   from a signing request, and convert certificate + key to PEM. Download Apple's
   "Worldwide Developer Relations - G4" certificate. The certificate expires yearly.
2. Google: create a Google Wallet *issuer* account and a Google Cloud service account
   with the Wallet API enabled, add the service account as a user of the issuer, and
   create a JSON key.
3. Set the secrets (PEM values may use `\n` for line breaks):

   ```bash
   supabase secrets set --project-ref <ref> --env-file wallet-secrets.env
   # APPLE_PASS_TYPE_ID, APPLE_TEAM_ID, APPLE_PASS_CERT_PEM, APPLE_PASS_KEY_PEM, APPLE_WWDR_PEM
   # GOOGLE_WALLET_ISSUER_ID, GOOGLE_WALLET_SA_EMAIL, GOOGLE_WALLET_SA_PRIVATE_KEY
   #   or, instead of the e-mail + key: GOOGLE_WALLET_SA_JSON = the whole JSON key file
   ```

   Never commit these. Until a platform's secrets are set, its button answers "not enabled yet".
4. Apply the two wallet migrations, then deploy:

   ```bash
   supabase functions deploy student-wallet-pass wallet-apple-web wallet-sync wallet-photo --no-verify-jwt --project-ref <ref>
   ```

**Tests**: `deno test supabase/functions/_shared/wallet/` (card contents, signing, delivery to
Google with a fake Google, photo links; no network) and `supabase/tests/local/wallet/` (end to end
on a local stack, see `tests/local/README.md`). The image library downloads its decoder while it
loads, so the tests that use it are skipped unless run as
`deno test --allow-net=deno.land supabase/functions/_shared/wallet/artwork_test.ts`.

## Edge Functions

Shared code lives in `functions/_shared/` and each function's `index.ts` is a thin entry.

| What | Where |
|---|---|
| CORS, JSON answers, errors | `_shared/http.ts` |
| The two Supabase clients (made once per isolate) and the session check | `_shared/clients.ts` |
| Who is an admin and which company they may act on | `_shared/admin-auth.ts` |
| Creating / deleting sign-in accounts with their profile rows (and undoing a half-made one) | `_shared/accounts.ts` |
| Registering a student | `_shared/create-student.ts` |
| Push notifications | `_shared/push/` |

`deno test supabase/functions/_shared/` runs every unit test (fake clients and fake fetch, no
network, no permissions). `deno check supabase/functions/*/index.ts` type-checks every function.
