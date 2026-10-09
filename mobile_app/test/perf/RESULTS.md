# Mobile performance pass: measurements

Commands (from `mobile_app/`):

    flutter test test/perf/image_benchmark_test.dart
    flutter test test/perf/request_count_test.dart
    flutter test test/perf/student_flows_test.dart
    flutter test test/perf/supervisor_request_count_test.dart

What these are, and are not:

- Image timings are pure Dart under `flutter test` on the development Mac
  (median of 3 runs per sample). They are a proxy for a phone, which is several
  times slower; they are not device measurements.
- Request counts come from counting fakes of the server placed below the
  repositories (`test/support/perf_fakes.dart`). Repositories, providers, saved
  copies and the live-event mapping are the real code. Ride-vote reads are
  counted at the repository (each read is at most one request).

## Before (2026-10-09, code as it was, with only the counting seams added)

### Receipt image preparation (`ImageOptimizer.receipt`, always run)

| sample | input | median time | stored | size |
|---|---|---|---|---|
| camera photo 4000x3000 JPEG | 4194 kB | 2874 ms | 853 kB | 1800x1350 |
| screenshot 1170x2532 PNG | 190 kB | 1604 ms | 439 kB | 832x1800 |
| picked as before 2600x1950 JPEG q92 (what the picker handed over) | 1771 kB | 2602 ms | 736 kB | 1800x1350 |
| picked at target 1800x1350 JPEG q85 | 591 kB | 182 ms | 596 kB | 1800x1350 |
| already small 900x600 JPEG | 131 kB | 42 ms | 132 kB | 900x600 |

### Requests per flow

| flow | requests | detail |
|---|---|---|
| (a) receipt upload, tap to settled, with echo | 15 | 7 before the echo (pre-check, upload, insert, current, all, catalog, receipts) + 8 for the echo (current, all, receipts, catalog, pass: 2 reads + sign + wallet refresh) |
| (b) approval arriving as a live event | 8 | current, all, receipts, catalog, pass: 2 reads + sign + wallet refresh |
| (c) student cold start, warm cache | 24 | role 3 selects; pass fetched twice (2x: 2 reads + sign + wallet refresh); vote settings 2; ride range 4 + details 2; current, all, catalog, profile row + sign, supervisor photo sign |
| (d) profile photo change, with echo | 16 | 4 before the screen is released (upload, set, list, remove), 6 to settle (profile row + sign, pass: 2 reads + sign + wallet refresh), 6 again for the echo |

## After (2026-10-09, same tests; they now assert these numbers as upper bounds)

### Receipt image preparation

Both columns measured in the same run (the machine was busier than during the
"before" run above, so compare within this table, not across tables). "Always
optimise" is the previous path (`ImageOptimizer.receipt` on whatever was picked);
"now" is `ImageOptimizer.prepareReceiptBytes`, which leaves a ready file alone.

| sample | input | always optimise: time | stored | now: time | stored | size | path |
|---|---|---|---|---|---|---|---|
| camera photo 4000x3000 JPEG | 4194 kB | 5610 ms | 853 kB | 5360 ms | 853 kB | 1800x1350 | optimised |
| screenshot 1170x2532 PNG | 190 kB | 3137 ms | 439 kB | 2887 ms | 439 kB | 832x1800 | optimised |
| picked as before 2600x1950 JPEG q92 | 1771 kB | 6004 ms | 736 kB | 5550 ms | 736 kB | 1800x1350 | optimised |
| picked at target 1800x1350 JPEG q85 | 591 kB | 382 ms | 596 kB | 26 ms | 591 kB | 1800x1350 | as picked |
| already small 900x600 JPEG | 131 kB | 88 ms | 132 kB | 2 ms | 131 kB | 900x600 | as picked |

How to read it for the app:

- Before, the picker handed over 2600 px at quality 92 and Dart always shrank it:
  the "picked as before" row (2602 ms in the quiet run, 6004 ms in the busy one).
- Now the picker is asked for 1800 px at quality 85, so what arrives is the
  "picked at target" row: 26 ms (an isolate round trip, no decoding), and that
  work starts when the image is picked, not when "send" is tapped. Stored size
  for a photo: 736 kB before, 591 kB now.
- The optimiser itself is unchanged for files that still need it (PNG
  screenshots the picker did not convert, files over 1.5 MB, sideways photos):
  those rows cost what they cost before.
- The resize itself moved to the platform's picker; its time is not measured
  here (it happens inside the picker, before the app gets the file).

### Requests per flow

| flow | before | after | detail (after) |
|---|---|---|---|
| (a) receipt upload, tap to settled, with echo | 15 | 2 | upload + insert. Nothing is read again; the echo costs 0. (The "proof received" notice arriving with it reads the inbox once: 1 request for new content, not counted in either column.) |
| (b) approval arriving as a live event | 8 | 7 | current, all, receipts, catalog, pass: 2 reads + wallet refresh. The photo link is reused (no sign). An approval does change the card and the catalog, so they are read. |
| (c) student cold start, warm cache | 24 | 13 | role 1 (RPC); pass once (2 reads + wallet refresh); vote settings 1; ride range 1 + details 1; current, all, catalog, profile row; 2 signs (student photo, supervisor photo) |
| (d) profile photo change, with echo | 16 | 5 | 2 before the screen is released (upload, set); 1 sign for the new photo; list + remove of old files in the background; the echo costs 0 |

Not measured here (needs a device): upload time on a phone and a mobile
network, the behaviour of the progress bar on a slow connection, the picker's
own resize time on Android and iOS.

## Data-access audit (2026-10-09, second pass)

Every remaining flow of both roles, by request. "Before" is the state the
first pass left (the "After" column above). Where a number is marked
*measured* it is asserted by a test; *read* means it was counted by reading the
code as it was (the old code had no seam to count it with).

What changed, in one line each:

- The card (QR pass) no longer reads anything: it is put together from the
  student's own row and the current subscription, which the home screen reads
  anyway. Before, it ran its own copy of both queries.
- The student's own row is read once for the home screen, the profile, the card
  and the forced-password check (`must_change_password` was a fourth read of
  the same row, on every start).
- The week's ride votes and the ride day's choices are one read, not two.
- The Wallet card is refreshed once a day in a run of the app, not every time
  the card's data is read.
- A read mark, a scan, and a notification a supervisor sends are no longer read
  again when the server announces them back to the phone that made them.
- A supervisor's phone reads nothing for changes in the company that its
  screens do not show (receipts, payment methods, prices, the Wallet design,
  password resets, invitations).
- Rider counts: every line in one request (`get_lines_rider_counts`), the
  lines taken from the dashboard; on a database without that function, one
  request per line as before.
- After a scan the day's numbers and the trip list are read once, not three
  times (the scan itself, its live echo, leaving the scanner).

### Student

| flow | before | after | detail (after) | how |
|---|---|---|---|---|
| (c) cold start, warm cache, as the test counts it | 14 | 11 | role 1; current, all, catalog, profile row; invitations 1; vote settings 1; ride votes 1; Wallet refresh 1; 2 signs. (The first pass reported 13: it did not count the invitations read, which is now behind a counted seam.) | measured |
| ... the same start in the real app, with what the test does not model | 17 | 13 | + inbox first page 1, + push device registration 1; the `must_change_password` read is gone (1 to 0) | read |
| home tab, opened again | 0 | 0 | kept for the session | measured |
| home: ride votes (start, resume, minute tick on a new ride day) | 2 | 1 | `ride.days`: the week and the ride day's choices | measured |
| ride confirmation (vote) | 1 | 1 | the RPC; the screen and the reminders use its answer. No live event reaches the student for it | read |
| the card's own reads (part of the start above; again on each refresh of it) | 3 | 0 (+1 a day) | nothing of its own; the Wallet refresh once a day in a run | measured |
| card tab opened / opened again / pull to refresh | 0 / 0 / 3 | 0 / 0 / 2 | pull to refresh reads the two shared reads | measured / read |
| subscriptions tab opened (its list and the catalog are part of the start above) | 0 (+1 or 2 per open card) | 0 (+1 or 2 per open card) | an open unpaid card reads its receipts and the company's payment methods once, an approved one its issued receipt once; all kept for the session | read |
| purchase flow: company, line, station, period, review | 0 | 0 | every step is the catalog already loaded | read |
| create subscription, with echo | 5 | 2 | insert + catalog (what is on sale does change). Before, the card read 2 + Wallet refresh | measured |
| (a) receipt upload, with echo | 2 | 2 | upload + insert | measured |
| (b) approval arriving as a live event | 7 | 4 | current, all, receipts, catalog | measured |
| profile details saved, with echo | 1 | 1 | the RPC | measured |
| (d) profile photo, with echo | 5 | 5 | upload, set, sign, list + remove of old files | measured |
| forced password change | 2 | 1 | the function; the flag is corrected on the phone from it | read |
| Notification Center opened | 0 (+1) | 0 (+1) | the first page is the bell's; + the coming week's votes for the reminder strip | measured / read |
| older page | 1 | 1 | per page | measured |
| mark read / mark all read | 2 | 1 | the write; its own "read" announcement is not read again | measured |
| read on another phone (live) | 1 | 1 | the first page | measured |
| invitation declined | 1 | 1 | the list is corrected from the answer | measured |
| invitation accepted, with echo | 6 | 3 | answer + current + all (the answer does not hold the new subscription); + catalog when the subscriptions tab shows it | measured |
| back in the app / reconnect | 13 | 9 | current, all, open card's receipts, catalog, profile, invitations, vote settings, ride votes, inbox | measured (ride votes and inbox counted apart) |
| offline start | 0 answered | 0 answered | every read above is tried once and falls back to its saved copy; the card needs no connection | read |

### Supervisor

| flow | before | after | detail (after) | how |
|---|---|---|---|---|
| (e) start (first, or with everything saved) | 4 (+1 inbox) | 4 (+1 inbox) | dashboard, own photo row + 1 sign, sale switches | measured |
| home tab, opened again | 1 | 0 | the sale switches were asked again on every return to the tab | measured |
| (f) trips tab, one direction / the other / back | 1 / 1 / 0 | 1 / 1 / 0 | one read per trip list, kept for the session | measured |
| (g) rider counts, N lines | 1 + N | 1 | `get_lines_rider_counts`; lines from the dashboard. 1 + N on a database without the function (asked once in a run) | measured |
| rider counts, leaving the page | 1 | 0 | the dashboard was read again on the way back | read |
| (h) scan from the scanner tab, with echo | 3 | 2 | check-in + dashboard | measured |
| scan from a trip, with echo, back to the list | 6 | 3 | check-in + dashboard + that trip's list | measured |
| a scan by another supervisor (live) | 2 | 2 | dashboard + the open trip list | measured |
| (i) a receipt, payment method, price, Wallet design, password reset, invitation, complaint in the company (live) | 2 each (+1 + N with rider counts open) | 0 | nothing a supervisor sees changed | measured |
| a student's vote (live) | 2 | 2 | dashboard + the open trip list (+1 with rider counts open, was 1 + N) | measured |
| (j) a month / another / back | 1 / 1 / 0 | 1 / 1 / 0 | per month, kept for the session | measured |
| (k) send a notification (free text or ready message), with echo | 3 | 2 | the send + one read of the inbox | measured |
| ready messages list | 1 | 1 | once in a session | read |
| back in the app / reconnect | 3 (+ open lists) | 4 (+ open lists) | dashboard, photo row, inbox, and the sale switches (kept now, so refreshed here instead of on every tab change) | read |

Still more than the minimum, and why it was left:

- The current subscription and the list of all subscriptions are two reads of
  the same rows (start, resume, every subscription event). The current one
  could be picked from the list on the phone; that moves a server rule (which
  subscription is "current") into the app and changes two saved copies, so it
  was not done here.
- An accepted invitation reads the subscriptions again, a scan reads the
  dashboard and the trip list again, and a sent notification reads the inbox
  again: their RPCs do not return the new rows.
- A supervisor's phone hears every notification of the company on the
  `company:` topic and reads its inbox's first page for each, including the
  personal ones sent to students. The event carries no audience, so the app
  cannot tell.
- The supervisor's photo path is its own read; it is not in the dashboard.

## The catalog on demand (2026-10-09, third pass)

`get_subscription_catalog` is the app's largest read (every line serving the
student's university: 570 kB for 228 lines) and was read at every start, on
every resume and on several live events, by students who were buying nothing.
It is now read only while something on screen shows it: the purchase flow, or
the "next period" card of a running subscription, and only while the
Subscriptions tab is in front. Everything else only marks it stale; it is read
again by whatever shows it next. Still from its saved copy first, and still
shown from that copy without a connection.

Where it was watched, and where it is now:

- `PurchaseFlow.build`: always, as soon as the flow was built (for a student
  with no subscription that is the tab warm-up, 1.2 s after start). Now only
  while `PurchaseFlow.visible`; behind another tab it shows what it last
  showed and listens to nothing.
- `SubscriptionScreen._payNextCard`: on every build of the tab for a student
  with a running subscription (again the warm-up). Now only while
  `SubscriptionScreen.visible` (the tab is the one in front).
- `subscriptionCreatorProvider` invalidated it while the purchase flow was
  still listening, which read it again for a student who was leaving the
  flow. The screen now marks it stale after the flow is off screen.

| flow | before | after | how |
|---|---|---|---|
| cold start, student with a subscription (test's count) | 11, catalog 1 | 10, catalog 0 | measured |
| cold start, student with no subscription | catalog 1 | catalog 0 | measured |
| Subscriptions tab opened, running subscription ("next period" card) | 0 (already read at start) | 1, once in a session | measured |
| Subscriptions tab opened, no subscription (purchase flow) | 0 (already read at start) | 1, once in a session | measured |
| the same tab opened again | 0 | 0 | measured |
| `lines` / prices / `subscriptions` event, purchase UI not in front | 1 | 0 (read when next shown) | measured |
| the same event with it in front | 1 | 1 | measured |
| approval arriving as a live event | 4 | 3 (current, all, receipts) | measured |
| back in the app / reconnect, purchase UI not in front | 9 | 8 | measured |
| create subscription, with echo | 2 | 1 (the insert) | measured at the providers; the screen's own step is read |

Left: a student with a running subscription who opens the Subscriptions tab
still reads the whole catalog once in a session, only to learn whether the
next period is on sale for their line and at what price. A small function
answering just that would remove it.
