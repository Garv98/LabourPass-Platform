# 🪪 LabourPass

**A portable, tamper-proof digital work identity & wage-protection passbook for India's 450M informal workers.**

Attendance, wages, and experience — entered by employers on a phone, delivered to workers as SMS/WhatsApp, cryptographically **tamper-evident**, and shareable with banks and welfare boards as a verifiable record. Built feature-phone-first; works **offline**; runs on a **₹0 stack**.

🔗 **Live:** https://labour-pass-platform.vercel.app

📂 **Repo:** https://github.com/Garv98/LabourPass-Platform

| Try it | How |
|---|---|
| **Employer** | Sign in with phone **9876543210** → OTP shows on the 📱 panel (tap **Copy OTP**) |
| **Admin** | **admin@labourpass.in** / **admin123** |
| **Worker passbook** | [/verify/passbook/LP-SUN001](https://labour-pass-platform.vercel.app/verify/passbook/LP-SUN001) |
| **Worker phone (SMS sim)** | [/phone](https://labour-pass-platform.vercel.app/phone) — text `PROFILE`, `WAGES`, `PASSBOOK`, `1`/`2` |

---

## The problem

India's informal economy is ~89% of jobs and ~50% of GDP, yet the worker is **economically invisible**: no attendance record, no wage receipt, no proof of experience. A 15-year mason can't prove a single day to a bank; a domestic worker owed months of pay has no recourse. Existing tools all assume a smartphone, internet, formal employment, or government intermediation — none of which the target worker has.

LabourPass gives the worker a record that **follows them**, that they don't depend on the employer to keep, and that a third party can actually trust.

---

## What it does

**Employer (mobile web / PWA)** — register workers, mark daily attendance (**works offline**, syncs on reconnect), record wage payments, issue experience certificates, see wage analytics & a trust score.

**Worker (any phone)** — every event arrives as **SMS / WhatsApp** (no app, no smartphone needed). The worker can text back `PROFILE`, `WAGES`, `PASSBOOK`, raise a `DISPUTE`, or rate a payment `1`/`2` — and gets a real reply. A public **passbook page** (web + printable PDF + QR) aggregates everything across all employers.

**Admin (desktop)** — approve/suspend employers, resolve disputes (state machine), monitor trust scores, view a **live informal wage index** (avg daily wage by skill/state), audit the SMS log, export CSV.

---

## What makes it stand out

| Feature | Why it matters |
|---|---|
| **Hash-chain tamper-evidence** | Every attendance/wage row is `sha256(fields ‖ prev_hash)`. The public verify page recomputes the chain and pinpoints any altered record. "Tamper-resistant" is **real**, not a slide — try the **Tamper / Restore** button on the passbook. |
| **Offline-first attendance** | Mark attendance with no network (IndexedDB queue + background sync) → auto-syncs on reconnect. The live "wow." |
| **Two-way real messaging** | Outbound wage/attendance + inbound `PROFILE/WAGES/DISPUTE/1-2` over **WhatsApp Cloud API**, plus a pixel-accurate **simulated SMS phone** for the feature-phone story (and offline/dev). One adapter swap → production SMS (MSG91/Twilio + DLT). |
| **Crowd-sourced Employer Trust Score** | Workers rate payment reliability by a single SMS reply → rolling-90-day score, "Verified Payer" badge, admin alerts on low scores. |
| **Live Informal Wage Index** | Ground-truth avg daily wage by skill & state — data India currently has no real-time source for. |
| **Govt-passbook design system** | Modeled on the MGNREGA job card / wage slip — manila stock, official-ink band, boxed registration cells, rubber stamp. Built *for* the user, not *about* them. |

---

## Tech stack (all free tier)

- **Frontend:** React + Vite + TypeScript + Tailwind v4 · TanStack Query · react-router · **Hind** font (Devanagari+Latin) → **Vercel**
- **PWA / offline:** `vite-plugin-pwa` (custom service worker, `injectManifest`) + **Dexie** (IndexedDB) + Background Sync + Web Push
- **Backend:** **Supabase** — Postgres + auto REST (RPC) + Realtime. **No app server**: the entire backend is `SECURITY DEFINER` SQL functions + a custom session-token table. All tables are **RLS-locked**; data flows only through token-validated RPCs.
- **Integrity:** Postgres `BEFORE INSERT` triggers (pgcrypto `digest`)
- **Real delivery / push:** Supabase **Edge Functions** (Deno) + `pg_net` triggers → WhatsApp Cloud API / Web Push
- **PDF** `jspdf` (lazy-loaded) · **QR** `qrcode` · **Charts** `recharts` · **i18n** `react-i18next`

---

## Architecture

```
React PWA (Vercel)
  /                merged sign-in hub (employer OTP + admin) + live phone
  /employer        offline-first dashboard, workers, attendance, wages, certs, trust
  /admin           approvals, disputes, trust, analytics, wage index, SMS log
  /verify/:type    public passbook & certificate + hash-chain verify (no login)
  /phone           simulated feature phone (Realtime SMS in/out)
        │ supabase-js (RPC + Realtime)
        ▼
Supabase Postgres
  SECURITY DEFINER RPCs · custom token sessions · RLS on every table
  hash-chain triggers · sms_inbound() parser · trust recompute
  Realtime(sms_logs) → phone panel
        │ pg_net triggers (outbound sms_logs / wage / attendance inserts)
        ▼
Edge Functions (Deno)
  notify-send    → WhatsApp Cloud API (allowlist-capped)
  meta-inbound   → incoming WhatsApp → sms_inbound() → reply
  send-push      → Web Push (VAPID)
```

---

## Run it locally (~10 min)

### 1. Create a Supabase project
[supabase.com](https://supabase.com) → New project (free tier).

### 2. Load the database
SQL Editor → paste **[`supabase/full_setup.sql`](supabase/full_setup.sql)** → Run. *(Idempotent — safe to re-run; the demo seed auto-skips if present.)*

### 3. Configure the frontend
```bash
cp .env.example .env.local
```
Fill from **Supabase → Settings → API**:
```
VITE_SUPABASE_URL=https://<ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<publishable / anon key>
VITE_PUBLIC_BASE_URL=http://localhost:5173
```

### 4. Run
```bash
npm install
npm run dev      # http://localhost:5173
```
That's the full app with the **simulated phone** — no provider accounts needed.

### 5. (Optional) Real WhatsApp / Push
Two-way WhatsApp, Web Push, and the delivery triggers are wired as Supabase Edge Functions. To enable real delivery, deploy the functions + set secrets + add the `pg_net` triggers — see **[`deploy.md`](deploy.md)** and the headers in each `supabase/functions/*/index.ts`. Real SMS to feature phones requires a DLT-registered gateway (MSG91/Twilio) — the adapter is in `notify-send`; flip one branch.

---

## 5-minute demo script

1. **Problem (20s):** 450M informal workers, zero proof of work.
2. **Register (30s):** add a worker → the 📱 phone buzzes with a welcome SMS.
3. **Offline wow (60s):** Attendance → DevTools ▸ Offline → mark workers → "pending sync" → back **Online** → it syncs, SMS fires.
4. **Wage + trust (45s):** record ₹9000 → receipt SMS → reply **2** on the phone → employer trust score drops live → admin red flag.
5. **Portability (45s):** open **/verify/passbook/LP-SUN001** → download the **PDF passbook** (official, QR-stamped).
6. **Tamper-proof (40s):** **Verify integrity** → ✓ intact → **Tamper a record** → "✗ tampering detected at block #2" → **Restore**. Crypto, not a slide.
7. **Scale (30s):** simulated SMS today; one adapter → MSG91 in production. ₹0 stack, real digital public infrastructure.

---

## Security notes

- All tables **RLS-locked**; access only via token-validated `SECURITY DEFINER` RPCs. Public verify RPCs return **PII-safe** fields (no phone/Aadhaar). Aadhaar stored **last-4 only**. Admin passwords **bcrypt** (`pgcrypto crypt`). Wage writes carry **idempotency keys**; every mutation hits an append-only **audit log**.
- **Demo-mode caveats** (by design, for the on-screen phone panel): `sms_logs` is publicly readable so the simulator can render messages — in production, OTPs would not be stored there and the read policy would be scoped. OTP generation uses `random()` (swap to crypto for production). State these on stage.

---

## Repo layout

```
supabase/migrations/   0001 schema+hashchain · 0002 auth+employer · 0003 public+admin ·
                       0004 rls · 0005 seed · 0006 extras · 0007 push · 0008 notify · 0009 register-update
supabase/full_setup.sql  one-paste consolidation of all migrations
supabase/functions/    notify-send · meta-inbound · send-push   (Deno edge functions)
src/lib/               supabase · api (typed RPC) · session · offline (Dexie) · push · pdf · csv · i18n
src/components/        PhoneSim · layouts · ui primitives · Emblem · QR · PushButton
src/pages/             employer/* · admin/* · verify/* · Landing (merged login) · PhonePage
```

## Roadmap
Real SMS via MSG91/Twilio + DLT · worker-confirmed (two-sided) records · UPI wage rail · E-Shram / PMJDY / BOCW integrations · lender API consuming the passbook as income proof. The architecture accommodates each as an adapter, not a rewrite.

---
