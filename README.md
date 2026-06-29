# 🪪 LabourPass — Digital Work Identity & Wage Protection

A **$0-stack, offline-first PWA** that gives India's informal workers a verifiable, portable
work identity — attendance, wages, experience certificates, and a crowd-sourced employer
**Trust Score** — all **tamper-evident** via an on-chain-style SHA-256 **hash-chain**.

Built for a national-level hackathon. Three surfaces (Employer PWA, Admin, Public Verify) on a
**pure-Postgres Supabase backend** with a **simulated SMS gateway** so the feature-phone /
zero-device-worker story stays alive at **zero cost**.

---

## ✨ What makes it win

| Differentiator | Why judges care |
|---|---|
| **Offline-first attendance** (Dexie + Background Sync) | Mark attendance with no internet → auto-syncs on reconnect. Live "wow." |
| **Tamper-evident hash-chain** | Every attendance/wage row is `sha256(fields ‖ prev_hash)`. Public verify recomputes the chain and pinpoints any altered record. "Tamper-resistant" is **real**, not a slide. |
| **Simulated SMS gateway** | Feature-phone reach demonstrated with an on-screen phone — $0, swap one adapter for MSG91 in prod. |
| **Crowd-sourced Trust Score** | Workers rate payment via a 1/2 SMS reply → rolling-90-day employer score, badges, admin alerts. |
| **Custom OTP login, no paid SMS** | Employer OTP renders on the simulated phone (hashed in DB). |
| **Multilingual** (Hindi/English UI + bilingual SMS) | Inclusive by design. |

---

## 🧱 Stack (all free tier)

- **Frontend:** React + Vite + TypeScript + Tailwind v4 · TanStack Query · react-router
- **PWA/offline:** `vite-plugin-pwa` (Workbox) + **Dexie** (IndexedDB) + Background Sync
- **Backend:** **Supabase** — Postgres + auto REST(RPC) + Realtime. **No Edge Functions** — the
  whole backend is `SECURITY DEFINER` SQL functions + a custom session-token table.
- **Integrity:** Postgres `BEFORE INSERT` triggers (pgcrypto `digest`)
- **PDF** `jspdf` · **QR** `qrcode` · **Charts** `recharts` · **i18n** `react-i18next`

---

## 🚀 Setup (≈10 min)

### 1. Create a Supabase project
[supabase.com](https://supabase.com) → New project (free tier). Wait for it to provision.

### 2. Load the database
Open **SQL Editor** → paste the contents of [`supabase/full_setup.sql`](supabase/full_setup.sql)
→ **Run**. (It runs schema → hash-chain → auth/RPCs → RLS → demo seed.)

> Or with the CLI: `supabase db push` after `supabase link`.

### 3. Configure the frontend
```bash
cp .env.example .env.local
```
Fill from **Supabase → Settings → API**:
```
VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR-ANON-PUBLIC-KEY
VITE_PUBLIC_BASE_URL=http://localhost:5173
```

### 4. Run
```bash
npm install
npm run dev
```
Open http://localhost:5173

---

## 🔑 Demo credentials (seeded)

| Role | How |
|---|---|
| **Employer** | Login with phone **9876543210** → OTP appears on the 📱 phone panel (right side / floating button) |
| **Admin** | **admin@labourpass.in** / **admin123** |
| **Public passbook** | `/verify/passbook/LP-SUN001` |
| **Worker phone sim** | `/phone` — type `PROFILE`, `WAGES`, `PASSBOOK`, `1`, `2`, `DISPUTE 12-Jun` |

---

## 🎬 5-minute demo script

1. **Problem (20s):** 450M informal workers, zero proof of work.
2. **Register worker (30s):** Employer → Workers → Register → the 📱 phone buzzes with a Hindi welcome SMS.
3. **Offline wow (60s):** Attendance tab → DevTools → Network **Offline** → mark workers → "pending sync"
   badge → go **Online** → it syncs and SMS fire on the phone.
4. **Wage + trust (45s):** Wages → Record ₹9000 → instant receipt SMS → "Send trust SMS" → on the
   phone reply **2** → employer Trust Score drops live → Admin shows a red flag.
5. **Portability (45s):** Open **`/verify/passbook/LP-SUN001`** (a "new employer's phone") → verified
   history + QR.
6. **Tamper proof (30s):** Click **Verify integrity** → "✓ N records intact." Then in Supabase SQL
   editor: `update wage_records set amount = 1 where reference_no = 'LP-W-002';` → reload verify →
   **"✗ Tampering detected — wage record #2 altered."**
7. **Scale (30s):** Simulated SMS today; production swaps one adapter to MSG91. $0 stack, real DPI.

---

## 🏗️ Architecture

```
React PWA (Vercel)
  /employer  offline-first dashboard (Dexie + service worker)
  /admin     approvals, disputes, trust, analytics
  /verify/*  public certificate & passbook + hash-chain verify
  /phone     simulated feature phone (Realtime SMS in/out)
        │ supabase-js (RPC + Realtime)
        ▼
Supabase Postgres
  SECURITY DEFINER RPCs (auth, employer, admin, public, sms_inbound)
  custom session tokens · RLS locks all tables · hash-chain triggers
  Realtime on sms_logs → powers the phone simulator
```

Security: all tables RLS-locked; data flows only through token-validated RPCs; public verify RPCs
return PII-safe fields (no phone/Aadhaar); Aadhaar stored as last-4 only; OTP hashed; admin
passwords bcrypt (`pgcrypto crypt`).

---

## ☁️ Deploy (free)

- **Frontend → Vercel:** import repo, set the 3 `VITE_*` env vars, deploy. SPA rewrites in `vercel.json`.
  Set `VITE_PUBLIC_BASE_URL` to your Vercel URL so QR/links resolve.
- **Backend → Supabase cloud** (already there).

---

## 📁 Layout

```
supabase/migrations/   0001 schema+hashchain · 0002 auth+employer · 0003 public+admin · 0004 rls · 0005 seed
supabase/full_setup.sql  one-paste consolidation of the above
src/lib/               supabase, api (typed RPC), session, offline (Dexie), pdf, csv, i18n, constants
src/components/         PhoneSim, layouts, ui primitives, QR, Modal
src/pages/             employer/* · admin/* · verify/* · auth · phone · landing
```

## 🛣️ Production roadmap (deferred, by design)
Real MSG91/Exotel gateway · Bull/Redis queue · AES-256 Aadhaar at rest · RS256 + refresh rotation ·
read replicas · E-Shram / PMJDY / BOCW integrations. The architecture already accommodates each as
an adapter/infra swap, not a rewrite.
