# Basak — University Bus Subscription Platform

A multi-tenant platform for managing university bus subscriptions, built for students, bus supervisors, and transport companies.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (iOS & Android) |
| Admin Dashboard | React + Vite + Tailwind CSS |
| Backend | Supabase (Postgres, RLS, Realtime, Edge Functions, Storage) |

## Structure

```
basak/
├── mobile_app/     # Flutter app — students & supervisors
├── admin_web/      # React dashboard — company & platform admins
└── supabase/
    ├── migrations/ # All schema changes, applied in order
    └── functions/  # Edge Functions (auth, subscriptions, reset)
```

## Getting Started

**Backend** — apply `supabase/migrations/` in order, then deploy Edge Functions:

```powershell
npx supabase login
powershell -File supabase/deploy-functions.ps1
```

**Admin dashboard:**

```bash
cd admin_web && npm install && npm run dev
```

**Mobile app:**

```bash
cd mobile_app && flutter pub get && flutter run
```

## Key Rules

- One active subscription per student at a time
- Daily ride confirmation key locks at 1:00 PM automatically
- Companies with no governorates set are hidden from students
- Receipt review allows up to 5 upload attempts; rejection requires a written reason
- Supervisor and admin accounts are created by admins only — no self-registration
