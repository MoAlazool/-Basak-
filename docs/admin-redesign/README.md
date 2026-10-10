# Admin dashboard redesign — design stage

The web dashboard (`admin_web/`) is being redesigned for both roles: the
company admin (a transport company's owner, often a driver, new to software,
mostly on a phone in a browser) and the super admin (the platform).
**Nothing in `admin_web/` has changed yet**: this folder and the boards are the
design, to be approved before the build starts.

Live canvas: https://claude.ai/artifact/NveQBomjGxfsYtg6W5LWdk (sections 16–44).

## What is here
- `audit.md` — the audit of the current dashboard, from the code: page
  inventory, the company admin's real tasks, every form's fields, responsive
  facts, states, and the problems found, each with `file:line`.
- `generator/` — the Node scripts that write the artboards. `kit.mjs` holds the
  shared shell and components, `README.md` in it explains how a page is drawn
  and holds the navigation trees and final Arabic labels for both roles. One
  `gen-<batch>.mjs` per batch (`people`, `lines`, `money`, `platform`).
- `../canvas/Adm*.dc.html` — the 247 artboards (index: `../canvas/canvas.json`).
  Every page is drawn at desktop 1440 and phone web 390, with its dialogs,
  side panels and states.

## Direction
A responsive web dashboard in the app's own brand (ink, teal, Readex Pro).
Desktop: a side navigation with every destination visible and grouped, a top
bar with student search, real tables, side panels. Phone: a browser page with a
top bar and a menu drawer; tables become record cards. The first page is
«اليوم»: what needs the admin now, and tomorrow's riders per line.

## Before building
The boards assume some backend work that does not exist yet; each batch's
needs are listed in the audit and in the generator's notes. The main ones:
riders per line and per trip wired to the existing `get_lines_rider_counts*`
functions, filters and sorting for the students list, one all-or-nothing line
save, a supervisor password reset, revenue totals by line and by payment
method, and a reason on rejecting a data correction. Deleting a supervisor
today cascades to the boarding records he scanned
(`supervisor_scan_events.supervisor_id ON DELETE CASCADE`); that should change
before the delete action is made easier to reach.

All names, prices, phone numbers and payment addresses on the boards are
sample content.
