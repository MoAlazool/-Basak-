# Basak (باصك) — iOS App Store release checklist

Branch `release/ios-readiness` (from `main` at `b22c995`, 2026-10-19). App version `1.0.18 (47)`.
Nothing here publishes anything: the signed build and the TestFlight upload run only when the owner
starts them, and submission for review stays a manual step in App Store Connect.

## 1. Status

| Area | State | Evidence |
|---|---|---|
| Flutter analyze | Clean | `flutter analyze`: no issues (Flutter 3.47.7) |
| Flutter tests | 1,245 pass, 0 fail (65 skipped as before) | `flutter test` on Linux; the 4 small-phone/duplicate-text failures that had been failing for weeks are fixed |
| Dashboard | 415 vitest pass, `tsc` clean | `admin_web` |
| SQL suite (local Postgres, all migrations) | 19 pass; 5 fail as before | The 5 rely on parts the local stub lacks (`auth.users.last_sign_in_at`, `realtime.messages`); unchanged by this branch |
| iOS build on Xcode 26 | **Not yet run** | `.github/workflows/ios-release.yml` is in place, but GitHub Actions starts no jobs on this repository, not even `ubuntu-latest` (§5) |
| Live backend checks | **Not run** | This session has no access to the live project: the Supabase connector is denied, and the network policy blocks `*.supabase.co`. Run `docs/release/verify_live.sql` (§6) |
| Capacity | **Blocker** | §7 |

## 2. What this branch changes

**iOS project**
- iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only. The layouts are portrait-only; landscape and iPad were never designed. Dropping iPad also means no iPad screenshots and no iPad review.
- Release and Profile sign with `Runner/RunnerRelease.entitlements` (`aps-environment = production`). Debug keeps development.
- `ios/ExportOptions.plist`: App Store Connect export, automatic signing.
- `tool/ios_preflight.py` runs without a Mac. It checks:
  - a purpose string for each plugin that needs one;
  - `ITSAppUsesNonExemptEncryption`;
  - the scene life cycle (required for iOS 26 SDK builds);
  - the privacy manifest exists and is in the target;
  - the push environment of each configuration;
  - the bundle id against the Firebase iOS app;
  - the version.
- `tool/build_ios.sh`: a local Mac build with the same build values as CI.

**App (App Review risks)**
- **Cairo clock** (`lib/core/time/cairo_clock.dart`). Vote windows, ride days and "today" follow `Africa/Cairo`, as the server does, wherever the phone is set. App Review in the US previously saw wrong open/closed states and got server refusals.
- **Privacy policy and terms:**
  - «سياسة الخصوصية» and «شروط الاستخدام» rows on both profiles (5.1.1).
  - URLs are set at build time (`PRIVACY_URL`, `TERMS_URL`). The previous `https://basak.app/...` does not resolve.
  - The pages live in `admin_web/public/legal/` (`privacy.html`, `terms.html`, `delete-account.html`, `support.html`), served by the dashboard's Vercel site.
- **Account deletion:**
  - The dialog says issued official receipts stay with the company.
  - Errors show the server's words, never a raw `FunctionException`.
  - The supervisor profile says to ask the company to delete the account (5.1.1(v)).
- **First launch with no connection:** it now says "couldn't check your account" with a retry. Before, it showed "this account doesn't work here" with only a sign-out button.
- **App Store listing:** «تحديث من App Store» opens with `APP_STORE_ID`.
- **Apple Wallet:** the button can be switched off per build (`WALLET_ENABLED=false`) until the server can sign passes. A button that only answers «غير مفعّلة بعد» invites a 2.1 rejection.
- **Small phones:** the pay/renew action no longer overflows at 360 pt or with large text, and the sent time of a receipt under review is shown once.

**CI** (`.github/workflows/ios-release.yml`)
- `checks` (Linux): preflight, analyze, tests.
- `verify` (`macos-26`, Xcode 26+; fails on an older SDK): an unsigned release build of the real Xcode project, then a check of the built app.
- `ipa` (manual, environment `app-store`):
  - requires the privacy/terms pages to be live and free of placeholders;
  - archives with the App Store Connect API key and exports the IPA;
  - verifies the signature, bundle id, `aps-environment = production`, the privacy manifest and the encryption key;
  - keeps the IPA as an artifact;
  - uploads to TestFlight only when the checkbox is ticked.

## 3. Owner decisions and steps (Apple Developer / App Store Connect)

1. **Bundle id — done (2026-10-21).** App Store id `com.basak.basakMobile` on team `ELD3N9M4AP`. A Firebase iOS app is registered under it («Basak iOS (App Store)», `1:1011211335071:ios:3631efffa56c5bc21a79aa`) and `firebase.defines.json` carries its values; the preflight passes. The App ID exists with Push Notifications (Xcode automatic signing). The older Firebase iOS app `com.mohamedadel.basak` was only for development builds.
   - Previous note, for history:
   - Xcode is `com.basak.basakMobile`. The Firebase iOS app is `com.mohamedadel.basak`. iOS push needs them to match.
   - Pick the App Store id. Then either register a new Firebase iOS app under `com.basak.basakMobile` and update `FIREBASE_IOS_APP_ID` / `FIREBASE_IOS_API_KEY` (removing `FIREBASE_IOS_BUNDLE_ID`), or keep the Firebase one and set the repository variable `IOS_BUNDLE_ID=com.mohamedadel.basak`.
   - Create the App ID in Certificates, Identifiers & Profiles with **Push Notifications** enabled.
2. **APNs:** create an APNs auth key (.p8) and upload it in Firebase → Project settings → Cloud Messaging → Apple app configuration.
3. **Apple Wallet:**
   - Either create a Pass Type ID with its certificate and set the wallet secrets on the server (`APPLE_PASS_TYPE_ID`, `APPLE_TEAM_ID`, the pass certificate; see `supabase/functions/_shared/wallet`),
   - or set the repository variable `WALLET_ENABLED=false` for this release.
4. **App Store Connect API key:** Users and Access → Integrations → App Store Connect API, role **Admin**, so Xcode cloud signing can create the distribution certificate and profile.
5. **GitHub repository settings:**
   - **Actions must run first.** Today every job stays queued. Check Settings → Actions → General (Actions allowed), Billing → Actions minutes/spending limit (macOS minutes count 10× on private repositories), and that the account has no hold.
   - Secrets: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` (`base64 -i AuthKey_XXXX.p8`). Optionally `IOS_DIST_CERT_P12_BASE64` and `IOS_DIST_CERT_PASSWORD`.
   - Variables: `PRIVACY_URL`, `TERMS_URL` (for example `https://<dashboard-domain>/legal/privacy.html`), `APP_STORE_ID` (after step 7), and `IOS_BUNDLE_ID` / `WALLET_ENABLED` if they apply.
   - Environment `app-store` with yourself as required reviewer.
6. **Legal pages:**
   - Replace every `[بريد الدعم]` / `[support email]` / `[رقم واتساب الدعم]` in `admin_web/public/legal/*.html` (marked `REPLACE_BEFORE_PUBLISHING`).
   - Merge, and let Vercel deploy.
   - Open the four pages in a browser.
7. **App Store Connect → New App:**
   - Platform iOS. Name **باصك**. Primary language **Arabic**. The bundle id from step 1. SKU e.g. `basak-ios`.
   - Copy the numeric Apple ID into `APP_STORE_ID`.
   - After the first release, set the iOS store URL in the dashboard (app versions), so the in-app update prompt can open it.
8. **Build:** Actions → *iOS release* → Run workflow on `release/ios-readiness` (or `main` after merge). Tick *Upload to TestFlight*. Use a build number above any earlier upload.
9. **TestFlight:** install on a real iPhone and run the test plan in §8.
10. **Submit for review:** only after §6, §7 and §8 are done.

## 4. App Store Connect metadata (draft, Arabic primary)

- **Name:** باصك
- **Subtitle (≤30):** اشتراك باص الجامعة بسهولة
- **Category:** Travel (primary), Education (secondary)
- **Price:** Free; no in-app purchases
- **Keywords (≤100):** باص,اتوبيس,جامعة,اشتراك,مواصلات,طلاب,تذكرة,رحلة,مشرف,ترم
- **Description:**
  > باصك يجمع اشتراك باص الجامعة في مكان واحد. اختر خط شركتك ومحطتك وموعدك، وادفع للشركة بالتحويل وارفع صورة الإيصال، وتصلك الموافقة بإشعار. بطاقتك ورمزها على هاتفك، ويمسحها المشرف عند الصعود. أكّد ركوبك كل يوم ليعرف المشرف عدد الركاب، وتابع أيام اشتراكك ورحلاتك. للمشرفين: مسح البطاقات، ركاب كل رحلة، والتواصل مع الطلاب.
  > الدفع لشركة النقل مباشرة، ولا يتم أي دفع داخل التطبيق.
- **Support URL:** `https://<dashboard-domain>/legal/support.html`
- **Privacy Policy URL:** `https://<dashboard-domain>/legal/privacy.html`
- **Age rating:** answer **None** to every content question. There is no unrestricted web access and no public user-generated content (receipts are private). This gives 4+.
- **Export compliance:** the build declares `ITSAppUsesNonExemptEncryption = false` (HTTPS/TLS from iOS only), so App Store Connect asks nothing.
- **Screenshots:** 6.9" iPhone (1320 × 2868), required. Suggested five:
  1. student Home (ride card);
  2. the card with QR;
  3. the subscription page;
  4. choosing a line and period;
  5. the supervisor scanner result.

  Take them from the demo accounts in §6 on a real device or a simulator, with Arabic system language.

### App Privacy ("nutrition label")

Must match `ios/Runner/PrivacyInfo.xcprivacy`. Every type below is **linked to the user**, and none is **used for tracking**. Tracking: **No**.

| Category → type | Purpose |
|---|---|
| Contact Info → Name, Email Address, Phone Number | App Functionality |
| User Content → Photos or Videos (profile photo, receipt photos) | App Functionality |
| Purchases → Purchase History (subscriptions, receipts) | App Functionality |
| Identifiers → User ID, Device ID (push token / installation) | App Functionality |
| Usage Data → Product Interaction (ride confirmations, boardings, opened notices) | App Functionality, Analytics (shown to the company) |
| Other Data (university, college, specialisation, birth date) | App Functionality |

Not collected:
- location;
- contacts (the app only *adds* a supervisor's number to Contacts when asked);
- health, financial account info, browsing, diagnostics/crash data (no crash SDK).

## 5. App Review notes (paste into App Store Connect → App Review Information)

```
Basak is a subscription app for university buses in Egypt, run by licensed bus companies.
Students subscribe to a company's bus line for a term or a single day; supervisors scan the
student's QR card when boarding.

Sign-in is phone number + password (no third-party login, so Sign in with Apple does not apply).
Demo student:     phone <REVIEW_STUDENT_PHONE>     password <REVIEW_STUDENT_PASSWORD>
Demo supervisor:  phone <REVIEW_SUPERVISOR_PHONE>  password <REVIEW_SUPERVISOR_PASSWORD>
The student already has an active subscription, so Home, the QR card, the daily ride
confirmation and the subscription page all show real content. The supervisor is assigned to
the same line and can open its trips and scan the demo student's card (the card is on the
student's "بطاقتي" tab; you can scan it from a second device, or view the trip lists without
scanning).

Payments: the subscription is a physical transport service consumed outside the app
(guideline 3.1.3(e)). The student pays the bus company directly by bank/wallet transfer and
uploads a photo of the transfer receipt, or pays cash on the bus for a single day. No digital
content is sold and nothing is paid inside the app.

Times: ride confirmation opens and closes on Cairo time (Africa/Cairo), whatever the device's
time zone.

Account deletion: student → حسابي (Profile) → حذف الحساب (Delete account). Supervisor accounts
are created and deleted by their company (stated on the supervisor's profile).

The app is in Arabic (right to left).
```

### Demo accounts (owner, with approval; production data)

Create them **from the admin dashboard**. The dashboard calls the Admin Auth API through the edge functions, so each account is a real Auth user; never insert users with SQL. **Do not use الريتاج** or the super admin.

1. Platform → Companies → add a company named «باصك — مراجعة Apple». Give it a governorate.
2. In that company:
   - add a payment method;
   - add a line to a real university with one departure and one return trip and a term price;
   - turn the term on for sale (subscription periods).
3. Students → «إضافة طالب» with a phone you control, on that line, for the current term. It is created «بانتظار الدفع». Then open the student and choose «تفعيل بعد دفع نقدي», so it is **active**.
4. Supervisors → add a supervisor on that line.
5. Sign in with both accounts on a real iPhone before submitting, and check:
   - the student's Home, card, ride confirmation and subscription;
   - the supervisor's trips and scan.
6. Keep the company **active** during review. Afterwards, stop it from the dashboard; do not delete it.

## 6. Live backend checks (owner runs; read only)

- Supabase → SQL Editor → run `docs/release/verify_live.sql`. It runs in a `READ ONLY` transaction and prints counts only.

  | Expect | Means |
  |---|---|
  | `bench schema exists = false`, `bench auth accounts = 0`, `BENCH companies = 0` | Load-test leftovers are gone |
  | `public tables without RLS = 0` | Every public table has row level security |
  | `receipts bucket private = true`; public buckets only `offer-assets, wallet-assets` | Private files stay private |
  | `push configured = true` | Push can be sent |
  | `cron failures 24h = 0` | Scheduled jobs are healthy |

- Supabase → Edge Functions: **`bench-admin` and `bench-load` must not exist.** `bench-admin` accepts the same `x-dispatch-secret` as `push-dispatch`. Delete both, then rotate `PUSH_DISPATCH_SECRET`: update the function secret and `public.push_runtime.dispatch_secret` together.
- If leftovers remain:
  - review and run `perf/live/clean_bench.sql` yourself; it touches only BENCH companies and `@bench.busak.app` accounts, never الريتاج or the super admin;
  - delete the bench Auth users through the Admin API (`bench-admin` delete, before deleting that function);
  - then `DROP SCHEMA bench CASCADE`.
- Supabase → Authentication → turn on leaked-password protection.

## 7. Capacity (launch blocker until retested)

Measured on the live Free/Nano instance (`docs/audit/2026-10-CAPACITY.md`, R4):

| Concurrent active students, one-request launch | Result |
|---|---|
| 100 | 0 errors, p95 ≈ 0.2 s |
| 150 | Failed: disk I/O wait ~85% |
| 200 | Failed: disk I/O wait ~85% |

The old launch failed at 100. The one-request launch ships with this app version.

**Not resolved for a launch that can exceed ~100 students opening the app at the same minute.** Before launch, do one of these:

- **(a) Stay on Free/Nano.** Confirm the expected peak (all companies' students opening at the same moment, e.g. when the vote opens at 16:00) stays under 100. Re-run R4 after §6's cleanup on the clean database.
- **(b) Upgrade to Pro with Small compute or larger.** Re-run R4 at 150/200 and record it.

Either way, the result goes into the capacity report before submission.

## 8. TestFlight test plan (real iPhone, Arabic, any time zone)

**Student**
- Sign up a new student: legal links open and the checkbox works.
- Sign in; Home shows the ride card. With the phone set to e.g. US time, the vote state still matches Cairo time.
- Confirm today's ride and change the times.
- Card tab: QR shows; Add to Apple Wallet works, or is hidden when `WALLET_ENABLED=false`.
- Subscription: buy a term (bank transfer). Upload a receipt from the camera and from the library; the permission prompts show the Arabic purpose strings.
- Admin rejects the receipt: a push arrives with the reason, and the app shows the rejection. A new upload works.
- Admin approves: push, card active, official receipt viewable and saveable.
- Notifications: allow, background the app, receive a push; the badge clears when the inbox is read.
- Profile: privacy and terms rows open the pages. Face ID sign-in on and off.
- Delete account: the confirmation shows; the app returns to sign-in. Signing in again fails (the account is gone).

**Supervisor**
- Sign in. Trips; scan the student's QR: allowed, blocked, wrong line.
- Contacts: add the supervisor's number from the student side.
- The profile says deletion goes through the company.

**General**
- Offline: airplane mode, then reopen. Saved data shows with its age, and actions say they need a connection.
- First launch offline after reinstall: retry screen.

## 9. Known, non-blocking

- **The daily (cash) booking** is for the next votable ride, but the option row and the card don't show the date (SUB-05).
- **No crash reporting** (FLOW-01). Add Crashlytics later, and declare Crash Data if you do.
- **Rating:** a custom "rate us" sheet comes before the system review prompt. It is low risk; calling `requestReview()` directly is safer under 5.6.1.
- **Phone numbers are not verified by OTP** (SEC-01).
- **The launch screen** is a plain teal background; the launch images are 1×1.
- **`ios/Podfile.lock` is stale** (no Firebase pods). `pod install` on the first Mac/CI build refreshes it; commit the new lock.
- **Wallet "added" confirmation:** after adding a pass, `PKPassLibrary.containsPass` may report "cancelled" without the Wallet entitlement for the pass type. The pass is still added.
