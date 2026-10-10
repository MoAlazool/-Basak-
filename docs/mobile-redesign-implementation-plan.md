# Basak mobile redesign — implementation plan

Hand-off for a fresh session. Read this file first, then `docs/mobile-redesign.md`, then open the canvas.

| Source | What it is |
|---|---|
| **Design canvas** — https://claude.ai/artifact/NveQBomjGxfsYtg6W5LWdk | 126 artboards, the source of truth for every screen. Each artboard is a file `project/<Name>.dc.html`; the index is `project/canvas.json`. Read one with the Artifact tool: `action: read`, the URL, `path: project/<Name>.dc.html`. Sizes, colours, radii and Arabic copy in those files are exact — copy them, do not approximate from memory |
| **Design document** — `docs/mobile-redesign.md` | The reasoning. A strategy · B design system · C screens · D flows · E states · F canvas → Flutter map · G first plan · H supervisor · I recap, rating, update · J design system 2 and Flutter mapping · K biometrics · L iPhone and Android · M coverage audit · open decisions |
| **App** — `mobile_app/` | Flutter, Arabic, RTL, light theme only. Riverpod, Supabase. Readex Pro (Regular, 500, 600, 700 bundled). Lucide icons through `lib/core/theme/app_icons.dart`. iOS 15.5, Android minSdk 24 |

**Where this plan and section G of the design document differ (phase numbers, file locations), this plan wins.** Everything else in the document stands.

## 1. Scope and the one hard rule

**Presentation layer only.** Files that may change: anything under a `presentation/` folder, the screen files that sit directly in a feature folder (`splash`, `onboarding`, `student_main_screen.dart`, the supervisor screens), `lib/core/widgets`, `lib/core/theme`, the new `lib/core/ui`, and tests.

**Do not change** providers, repositories, models, `core/sync` (SyncHub), `core/storage` (OfflineCache), any Supabase call, edge functions or migrations. A screen is rebuilt on top of the providers it already watches, and makes the same requests it makes today — `test/perf/request_count_test.dart` and `supervisor_request_count_test.dart` pin that.

**Logic that lives inside screen files stays as it is.** Some providers and classes are declared in presentation files, and tests import them from there: `paymentMethodsProvider` and `ReceiptSubmitter` in `subscription_screen.dart`, `saleCatalogProvider` in `purchase_flow.dart`, `studentQrProvider` in `student_qr_screen.dart`. When one of these files is rebuilt, those declarations keep their names, their bodies and their file; only the widgets around them change. Check every screen file for the same pattern before rewriting it.

If a board cannot be built as drawn without new data or a data-layer change, **stop and ask**. Do not work around it, and do not invent the data. Everything known to be in that position is in Phase 9.

## 2. What is decided

| Topic | Decision |
|---|---|
| Brand | The app's own ink `#17384A` and teal `#00658D` on ground `#F0F5F8`. No navy `#1E3A8A`, no baby blue. Readex Pro. Western digits everywhere |
| Student tabs | الرئيسية · اشتراكي · بطاقتي · حسابي — same four, same indices. Alerts open from the bell on Home |
| Tab bar | Option C: the existing `FloatingGlassNavBar` **restyled, not replaced** — solid white pill, 64 high, 16 from the edges, no blur, labels 11 px, the card tab's icon in an ink pill. On scroll the labels fold away and the pill drops to 52; every tab stays one tap away. `collapseOnScroll` is reused |
| One purpose per screen | Home = status, route, tomorrow's ride. اشتراكي = time and money. بطاقتي = what a supervisor reads off the phone. No sentence or data block is repeated across them |
| Home pass | A ticket: status and route above the tear; line, company and a button to the card below it |
| Subscribe | One builder in place of the five-step wizard: company → line cards → station sheet → period → review sheet. Same `SubscriptionDraft` underneath |
| Receipt PDF | No commercial register, no tax number. Footer: «جميع الحقوق محفوظة · © 2026 Basak.app» |
| Entry screens | Light ground, logo lockup, fields grouped in one card, the route rail as the sign-up stepper. No dark header, no decorative shapes |
| Supervisor Home | Rider counts first: going and returning totals, a column per trip, today and tomorrow by swipe (no day switch) |
| Student notification categories | No in-app toggles. Only the phone's own permission, with a row that opens the phone's settings |
| Help & support | A sheet built from a list passed in. No channel is hard-coded |

## 3. Decisions still open

Send these to the user **once, at the start, in one message**. Until answered, build the default in the last column — the defaults remove nothing that works today.

| # | Question | Default until answered |
|---|---|---|
| 1 | College list: fixed in the app or per university from the dashboard? Required? | A fixed list in the app plus «كلية أخرى» as free text; required. Saved as text, as today |
| 2 | Help & support: which channels, owned by whom? | The sheet takes an injected list; ship it with the supervisor's contact only |
| 3 | Separate supervisor sign-in, or keep the طالب / مشرف switch? | As drawn: its own screen from the entry screen. The role still comes from the server |
| 4 | «تذكّر رقمي» | Kept as today until a yes |
| 5 | Ride-reminder days explainer in Alerts | Not built |
| 6 | Wallet button | Apple's and Google's own buttons, new placement only |
| 7 | Supervisor tabs: four (الملخص under حسابي) or five | Four, as drawn |
| 8 | A successful scan closes itself after 2 s | Yes, success only |
| 9 | Supervisor notification category switches | **Keep** the existing preferences screen for supervisors, restyled |
| 10 | Call / WhatsApp / copy for a rider | As drawn — the manifest already shows the number |
| 11 | Student's phone number on the card | In «كل التفاصيل» only |
| 12 | What a scan is attributed to | **Today's behaviour**: the scanner tab sends no trip, the Trips entry pins one |
| 13 | Bus capacity on supervisor Home | Not built (no data) |
| 21 | Lock phones to portrait? | Rotation left as it is; build portrait and centre a 480 column on wide screens |
| 22 | Push explainer for students too; one rule for the sign-out question; iOS camera usage text | Explainer: yes (presentation only). Sign-out question: unchanged. Camera text: unchanged until a yes |
| 23 | One-day cash subscription | Kept, as the third period tile |
| 24 | English. `main.dart` lists `en` but the locale is fixed to `ar` and there are no ARB files. The Account boards draw a «اللغة» row | Arabic only, strings stay where they are, the language row is **not** shown. Moving strings to `AppLocalizations` is its own later task |

Numbers 1–23 follow the list at the end of `docs/mobile-redesign.md`; 24 is new here. 14–18 and 20 belong to Phase 9.

## 4. Guardrails (every PR)

1. **One screen per PR**; the old screen is deleted in the same PR. No long-lived parallel UI, no feature flag.
2. `flutter analyze` clean and `flutter test` green before and after. The safety nets:
   - flows: `subscription_flow_test.dart`, `receipt_upload_test.dart`, `receipt_pdf_test.dart`, `student_experience_test.dart`, `perf/student_flows_test.dart`
   - offline and sync: `offline_first_test.dart`, `offline_test.dart`, `sync_test.dart`, `user_isolation_test.dart`
   - shell and alerts: `floating_nav_bar_test.dart`, `notification_center_test.dart`, `notification_screens_test.dart`, `student_notifications_test.dart`
   - account and sign-in: `profile_section_test.dart`, `profile_photo_test.dart`, `role_detection_test.dart`, `university_search_test.dart`
   - request counts: `perf/request_count_test.dart`, `perf/supervisor_request_count_test.dart` — a rebuilt screen must not ask the server for more
3. **Keep the widget `Key`s.** Before touching a screen, list its keys (`grep "Key('" <file>`) and the tests that use them. Present today:
   - purchase: `flow-back`, `flow-step-*`, `company-*`, `line-*`, `station-*`, `option-daily`, `option-*`, `review-amount`, `review-edit-*`, `flow-confirm`
   - subscription and pay: `subscribe-again`, `sub-card-*`, `sub-toggle-*`, `amount-label`, `amount-value`, `next-period`, `payment-methods`, `payment-notes`, `receipt-pdf-*`, `receipt-image-*`, `receipt-preview`, `receipt-remove`, `receipt-send`, `receipt-phase-*`
   - home and card: `supervisor-card`, `supervisor-call`, `supervisor-whatsapp`, `supervisor-save`, `supervisor-copy`, `student-qr`
   - account and entry: `profile-change-photo`, `profile-edit`, `profile-college`, `profile-email`, `profile-birth`, `profile-save`, `signup`, `login`, and the onboarding `next` / `final` keys
   - Known to disappear with the design: `sub-toggle-*`, `review-edit-*`, `flow-step-*`. Known label changes in `floating_nav_bar_test.dart`: «الاشتراك» → «اشتراكي», «مسح QR» → «مسح», and the collapsed state. Update the test **in the same PR** and say so in its description. Never delete a test to get to green.
4. **No colour, radius, text style or duration literal in a screen.** At the end: zero `Color(0x`, `BorderRadius.circular(` and `TextStyle(` outside `lib/core/ui/` and `lib/core/theme/`.
5. **Direction**: `EdgeInsetsDirectional`, `AlignmentDirectional`, `TextAlign.start` — never left or right. Times, phone numbers and codes sit in an LTR `Directionality`.
6. **No `BackdropFilter`** in bars or lists. Two shadows only: card and floating.
7. Tap targets at least 48 × 48. Text scale honoured from 1.0 to 1.3. Nothing clips at 360 × 640.
8. **Copy comes from the canvas, character for character.** Money only through `formatMoney`, time only through `BasakUi.time12`.
9. A status is drawn only through `StatusChip`. One primary button per route.
10. Commit and push only when the user asks. Never skip hooks.

## 5. Phases

Phases 0–2 are sequential and single-threaded; every later file imports what they create. From Phase 3 on, each screen is independent and gets its own branch.

### Phase 0 · Baseline — no UI change
- Read both documents; skim every row of the canvas.
- Run `flutter analyze` and `flutter test`; put the numbers in the first PR description.
- Send the user section 3 in one message.

### Phase 1 · Tokens and theme
Boards: `System`, `SystemPlus`. Document: B, J.1, J.2.
- New `lib/core/ui/tokens.dart`: `BasakColors` as a `ThemeExtension` (the Dart name of every colour is printed beside its swatch on `SystemPlus`), `BasakText` (15 roles; Flutter `height` = line ÷ size), `BasakSpace`, `BasakRadius` (10 / 14 / 16 / 20 / 28 / full), `BasakMotion`, `BasakShadow.card` and `.floating`. Read through `context.colors` and `context.text`.
- `lib/core/theme/app_theme.dart` rebuilt from the tokens: buttons (teal, radius 16, height 54), inputs (sunken fill, no border, 2 px teal ring on focus), sheets, snackbars, page transitions (350 ms `easeInOutCubic`, the app's current value).
- `AppColors` and `AppTextStyles` stay as `@Deprecated` aliases pointing at the new values until the last screen is migrated.
- The recap's expressive palette and its four poster type roles are defined but used only by Phase 9.
- **Done when** the app runs with unchanged behaviour, all tests are green, and a sample widget can be written with no literal.

### Phase 2 · Components in `lib/core/ui`
Boards: `Components`, `ComponentsPlus`, `PassStates`, `NavOptions`.
Build in this order — the first eight cover most of every screen:

1. `BasakButton` (primary, secondary, quiet, danger; loading; disabled)
2. `BasakPage` (gutter 20, 16 rhythm, optional bottom dock) and `BasakBackHeader`
3. `GroupedFields` (label-over-value rows in one card) and `InlineError`
4. `InfoRows`
5. `StatusChip` (the six statuses) and `BasakTag`
6. `BasakSheet.show` (grabber, radius 28, safe area, system back closes it first)
7. `PassCard` + `RouteRail` — all six statuses from `PassStates`
8. `BasakTabBar` — the restyle of `FloatingGlassNavBar`, for both shells
9. `ConnectionStrip` (replaces `OfflineBanner`), `BasakToast` (replaces snackbars), `EmptyState`, `skeleton.dart` reshaped
10. `ChoiceTile`, `RadioCard`, `ChipChoice`, `LineCard`
11. `PhotoRing`, `FactGrid`, `InfoStrip`, `ProgressLine`
12. Supervisor set: `CountsHero`, `PagerDots`, `BarRow`, `StopRow`, `StatTile`, `Meter`, `ScanChrome`, `ResultHeader`

Notes:
- `lib/core/widgets/basak_ui.dart` already has classes named `BasakPage`, `BasakPill`, `BasakStatTile`, `BasakInfoRow`, `BasakMessageCard`. The new ones replace them screen by screen; avoid importing both files in one screen. **`BasakUi.time12` and the money formatter are kept.**
- Add the missing Lucide glyphs listed in J.2 to `app_icons.dart`.
- **Goldens**: there are none in the repo today and no CI. Add one golden per component at 360 and 390 wide, text scale 1.0 and 1.3, loading the real Readex Pro files the way `test/render_preview_test.dart` does. Goldens depend on the machine that drew them — generate and compare on the same OS.
- **Done when** every component on the two boards exists with its golden. The tab bar is the only user-visible change so far.

### Phase 3 · Student shell, Home, card
Boards: `Main`, `HomeRide`, `HomeConfirmed`, `HomeNew`, `HomeInvite`, `InviteSheet`, `HomePending`, `HomeNotOpen`, `HomeClosed`, `ContactSheet`, `PushExplain`, `PushBanner`, `Card`, `CardDetails`, `CardInactive`, `CardUnavailable`, `StateLoading`, `StateOffline`, `StatePartial`, `StateError`.
Files: `features/student/student_main_screen.dart`, `home/presentation/student_home_screen.dart` (split out `pass_card`, `ride_card`, new `ride_sheet.dart`), `supervisor_contact_sheet.dart`, `invites`, `qr/presentation/student_qr_screen.dart`, `notifications/presentation/push_permission_sheet.dart`, `core/widgets/greeting_header.dart`, `offline_banner.dart`.
- The ride question keeps its provider and `VoteSettings`; it gains the sheet and the blocked states (not open yet, closed, no times).
- The card is built from `studentQrProvider` plus the ride days Home already loads. Nothing new is fetched.
- Tab indices, `_selectTab` and `NotificationRouter` destinations do not change.

### Phase 4 · Subscribe, pay, subscription, receipt
Boards: `FlowCompany`, `FlowLines`, `FlowStation`, `FlowPeriod`, `FlowDaily`, `FlowConfirm`, `FlowEmpty`, `Pay`, `PayNoMethods`, `PayUpload`, `PayDone`, `PayExhausted`, `StateRejected`, `SubscriptionAwaiting`, `SubscriptionReview`, `Subscription`, `SubscriptionExpired`, `Receipt`, `Invoice`.
Files: `features/student/subscription/presentation/purchase_flow.dart` (+ new `station_sheet.dart`, `confirm_sheet.dart`), `subscription_screen.dart` (list only; new `pay_screen.dart` extracted from it), `receipt_card.dart`, new `receipt_screen.dart`, `receipt_pdf.dart`.
- `SubscriptionDraft`, `DraftStep`, `saleCatalogProvider`, `paymentMethodsProvider`, `ReceiptSubmitter`, `ReceiptPhase`, `ImageOptimizer` and the pending-receipt reconciliation are used exactly as they are. The builder is a new arrangement of the same steps.
- The purchase flow keeps its `PopScope`; the upload screen gets one.
- PDF: remove the `legal` line (register and tax number, `receipt_pdf.dart` near lines 128 and 289) and set the footer from the `Invoice` board. `receipt_pdf_test.dart` has a case about legal details — update it in the same PR.
- This phase carries the most tests. Do it as four PRs: builder, pay, subscription list, receipt.

### Phase 5 · Entry
Boards: `Splash`, `Onboarding1`–`4`, `Welcome`, `SignIn`, `SupSignIn`, `SignUp`, `SignUpStudy`, `UniversitySheet`, `CollegeSheet`, `SignUpPhoto`, `PhotoSource`, `PhotoAdjust`, `SignUpPassword`, `ForgotRequest`, `ForgotReset`, `ForcePassword`, `WrongRole`.
Files: `features/splash/splash_gate.dart`, `features/onboarding/onboarding_screen.dart` (`OnboardingController` kept), `features/auth/presentation/login_register_screen.dart`, `login_screen.dart`, `signup_screen.dart`, `forgot_password_screen.dart`, `force_password_change_screen.dart`, `university_picker_sheet.dart`, `auth_form_styles.dart` (retired), `core/widgets/photo_adjust_screen.dart`.
- Sign-up becomes four step widgets over the same `AuthRepository.signUp` call; the chosen college is passed in place of «غير محدد».
- Recovery keeps its logic: a 6-digit code issued by the company's admin, valid 30 minutes.
- The biometric boards in this row are Phase 9.

### Phase 6 · Alerts and account
Boards: `Inbox`, `InboxDetail`, `InboxEmpty`, `Profile`, `EditDetails`, `DeleteAccount`, `Help`.
Files: `features/student/home/presentation/notifications_screen.dart`, `features/notifications/presentation/notifications_page.dart`, `notifications_host.dart`, `notification_style.dart`, `features/student/profile/presentation/profile_screen.dart`, `profile_editor.dart`, new `help_sheet.dart`.
- Students lose the link to `notification_preferences_screen.dart`; the screen itself stays for supervisors (decision 9).
- Left out of `Profile` for now: the Face ID row (Phase 9) and the language row (decision 24).

### Phase 7 · Supervisor
Boards: every `Sup*` board. Document: section H, file map in H.6.
Files: `features/supervisor/**/presentation`, `supervisor_notifications_screen.dart`.
- One new **presentation-level** provider holds the chosen line and trip, so tabs stop losing it on switch. It stores a selection, it does not fetch.
- Home is rebuilt on `supervisorDashboardProvider`. `rider_counts_screen.dart` and `trip_riders_sheet.dart` retire into Home and Trips.
- Scanner: same RPC (`supervisor_check_in_student`), same six `CheckInOutcome`s, drawn from `SupScanStates`. Writes are still never queued offline — `SupScanOffline` says so.
- Order: shell and Home → Trips → scanner → messages → account and monthly → states.

### Phase 8 · Finish
- Delete `glass_scaffold.dart`, `glass_container.dart`, the deprecated theme aliases, the leftovers of `basak_ui.dart` (keeping the formatters), and every per-file `_ink` / `_teal` / `_canvas`.
- Sweep for guardrails 4 and 5; check every screen at 360 × 640 and at scale 1.3; set the status-bar icon colour per screen (dark icons on ground, light on the scanner).
- Walk the `Coverage` board line by line: every inline state and toast listed there has a home in the code.
- Walk the `Platforms` board: safe areas, back behaviour, permission explainers.

### Phase 9 · Later — each item needs the user's go-ahead and touches more than the UI
| Item | Boards | Needs |
|---|---|---|
| Sign in with Face ID / fingerprint | `SignInFace`, `SignInTouch`, `SignInPrompt`, `SignInBioFailed`, `BioEnable` | `local_auth`, an auth-layer change, Info.plist and manifest entries; decision 20 |
| Term recap | every `Recap*` board | The user's approval of every joke and title (all are drafts); a source for hours; decisions 14, 15, 18 |
| Store rating | `RateIOS`, `RateAndroid` | `in_app_review` and a rule for when to ask; decision 16 |
| App update | `UpdateAvailable`, `UpdateRequired` | A server source for the minimum and latest version; decision 17 |
| Specialisation field, bus capacity, student photo at scan, manual boarding, offline scan queue | — | Backend |
| English | — | ARB files and translated copy; decision 24 |

## 6. Per-screen checklist

1. Read the artboard file(s). List every element, every state, every string.
2. Open the existing screen. List the providers it watches, its keys, and the tests that touch it.
3. Build with `core/ui` components only. A missing component is added to `core/ui` first, with a golden.
4. Loading, empty, error and offline use the shared components; check the `Coverage` board for that screen's inline states and toasts.
5. Keys kept; tests updated in the same PR.
6. `flutter analyze`, `flutter test`. Then compare the running screen with the board at 390 wide, at 360 × 640, and at text scale 1.3. `RENDER_DIR=<dir> flutter test test/render_preview_test.dart` draws screens to PNG with the real fonts — extend it for the screen being rebuilt.
7. PR description: boards covered, tests changed and why, anything that differs from the board and why.

## 7. How to run it

- **Phases 0–2**: one session, high effort, no parallel agents. These files are shared by everything, and two writers produce two dialects.
- **Phases 3–7**: one screen per branch. Parallel agents fit here — one builds, one compares the result with the board and runs the tests. Sequential work at high effort reaches the same result more slowly.
- Stop for the user's review after Phase 2, and after the first screen of Phase 3 (Home): those two set the look of everything that follows.
- After each phase, report what merged, what the tests say, what was skipped and why.

## 8. Prompt for the new session

```
Read docs/mobile-redesign-implementation-plan.md, then docs/mobile-redesign.md, and open the design canvas linked at the top of the plan. If docs/ is missing in this checkout, bring it in first: git checkout claude/basak-mobile-redesign-a6a94c -- docs

You are implementing the Basak mobile redesign in Flutter (mobile_app/). I have approved the visual design on the canvas. Follow the plan exactly: presentation layer only, the guardrails in section 4, the phase order in section 5.

Start with Phase 0: run flutter analyze and flutter test, report the baseline, and send me the open decisions from section 3 in one message. Then do Phase 1 and Phase 2 and stop for my review before any screen is rebuilt.

Do not commit or push until I ask.
```
