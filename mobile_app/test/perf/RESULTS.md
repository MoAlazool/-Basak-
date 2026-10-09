# Mobile performance pass: measurements

Commands (from `mobile_app/`):

    flutter test test/perf/image_benchmark_test.dart
    flutter test test/perf/request_count_test.dart

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
