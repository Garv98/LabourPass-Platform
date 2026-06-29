# LabourPass — Deployment Plan (expert-reviewed)

## TL;DR
Ship the working app to **Vercel + Supabase (cloud)** first — that's a 10-minute,
zero-risk live URL and it's what wins a demo. Treat **Web Push as an optional Phase 2**,
done with standard VAPID Web Push (no Firebase), and framed as a *complement* for
smartphone workers + a real channel for employers — **not** an SMS replacement.

---

## Critical review of the original notes

| # | Original idea | Verdict | Correction |
|---|---|---|---|
| Premise | "No SMS gateway — all worker notifications via FCM Web Push" | ⚠ Breaks the thesis | Web Push needs a smartphone + installed PWA + permission + internet. That re-imposes the exact barrier LabourPass removes. Keep **SMS as the worker concept** (simulated now → MSG91 in prod). Push = employer channel + optional complement for smartphone workers. |
| 3 | FCM "with VAPID key" | ✗ Conflated | FCM (Firebase) and raw **Web Push (VAPID)** are different. Use **raw Web Push** via `web-push` — no Firebase project needed. |
| 3 | "Call requestPushPermission() silently on load" | ✗ Browsers block this | Permission must come from a **user gesture** (an "Enable updates" button). Auto-prompting is ignored/penalised by Chrome & Safari. |
| 3/5 | Push handler in the existing SW | ✗ Not possible as-is | vite-plugin-pwa uses `generateSW` (Workbox) — no `push` listener. Must switch to **`injectManifest`** + custom `src/sw.ts`. |
| 5 | Edge Function sends push | ⚠ Deno caveat | Supabase Edge Functions run **Deno**; Node's `web-push` won't import cleanly. Use a Deno-native lib (`@negrel/webpush`) or sign VAPID manually. |
| 4 | `save_push_subscription` granted to anon | ⚠ Enumeration | A public passbook has no session, so any caller could register a sub for any `public_id`. Fine for demo; for prod tie to a verified worker session. |
| 8 | "Delete .env.local before push" | ✓ Already safe | `.env*` is gitignored. Just confirm. Secrets live in the Vercel dashboard. |
| 7 | PhoneSim stays demo-only | ✓ Correct | But then demo (SMS) ≠ prod (push). Keep SMS as the prod worker story so the demo matches the pitch. |

---

## PHASE 1 — Ship the live app (do this first, ~10 min)

Nothing in the codebase needs to change. Supabase is already cloud-hosted.

### 1. Push the repo to GitHub
```bash
# .env.local is already gitignored — verify:
git check-ignore .env.local            # should print: .env.local

git init
git add -A
git commit -m "LabourPass: offline-first wage & work-identity PWA"
gh repo create labourpass --public --source=. --push   # or create on github.com and: git remote add origin … && git push -u origin main
```

### 2. Import to Vercel
- vercel.com → **Add New → Project** → import the repo.
- Framework preset: **Vite** (auto-detected). Build `npm run build`, output `dist` (auto).
- **Environment variables** (Project Settings → Environment Variables):
  | Key | Value |
  |---|---|
  | `VITE_SUPABASE_URL` | `https://<ref>.supabase.co` |
  | `VITE_SUPABASE_ANON_KEY` | your **publishable / anon** key (never the secret key) |
  | `VITE_PUBLIC_BASE_URL` | `https://<your-app>.vercel.app` (set after first deploy, then redeploy) |
- Deploy. SPA routing already handled by `vercel.json` rewrites; PWA icons + service worker already built.

### 3. Post-deploy
- Set `VITE_PUBLIC_BASE_URL` to the real Vercel URL → **redeploy** (so QR codes & SMS links resolve to production).
- Smoke test on the live URL: employer login (9876543210), offline attendance, wage + trust, `/verify/passbook/LP-SUN001` + tamper check, admin login.
- Lighthouse → confirm PWA installable.

### Phase-1 security notes (state these honestly in the pitch)
- **Simulated SMS** means `sms_logs` is world-readable (needed for the phone panel). On a public URL anyone can read any number's OTP → demo-grade auth only. Production: swap to a real gateway and remove the public `sms_logs` SELECT policy.
- All tables are RLS-locked; data flows only through token-validated RPCs; public verify RPCs return PII-safe fields; Aadhaar is last-4 only.

---

## PHASE 2 — Web Push, done right (optional, after Phase 1 is live)

Goal: real push notifications to **employers** (e.g. "worker raised a dispute", "trust
score dropped") and to **smartphone workers** as a complement to SMS. HTTPS is required —
Vercel provides it, so this only works on the deployed URL, not `localhost` http.

### A. Generate VAPID keys (once)
```bash
npx web-push generate-vapid-keys
# → Public Key  (goes to frontend env)   → VITE_VAPID_PUBLIC_KEY
# → Private Key (goes to Supabase secret) → VAPID_PRIVATE_KEY
```

### B. Switch the PWA to a custom service worker
`vite.config.ts` → change `VitePWA({ strategies: 'injectManifest', srcDir: 'src', filename: 'sw.ts', registerType: 'autoUpdate', … })`.
Create `src/sw.ts`:
- `precacheAndRoute(self.__WB_MANIFEST)` (keep offline shell + runtime caching from current config).
- `self.addEventListener('push', e => { const d = e.data.json(); self.registration.showNotification(d.title, { body: d.body, icon: '/icon-192.png', data: d.url }) })`
- `self.addEventListener('notificationclick', e => { e.notification.close(); clients.openWindow(e.notification.data || '/') })`

### C. Subscription helper — `src/lib/push.ts`
- `enablePush(saver)` — called from a **button**: `Notification.requestPermission()` → `registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(VITE_VAPID_PUBLIC_KEY) })` → pass the `PushSubscription` JSON to `saver`.
- Employer: add an **"Enable updates"** button on the dashboard → `saver = (sub) => employer.savePush(sub)`.
- Worker (smartphone only): on the passbook page show an **"Get wage alerts"** button (not auto) → `saver = (sub) => pub.savePush(publicId, sub)`. Label it "for smartphones — feature-phone workers get SMS".

### D. Migration `0007_push.sql`
```sql
create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  actor_type varchar(20) not null,          -- 'employer' | 'worker'
  actor_id   uuid not null,                  -- employers.id or workers.id
  endpoint   text unique not null,           -- dedupe by endpoint
  subscription jsonb not null,
  created_at timestamptz default now()
);
alter table push_subscriptions enable row level security;

-- employer (token-validated) saves own subscription
create or replace function emp_save_push(p_token text, p_sub jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  insert into push_subscriptions(actor_type, actor_id, endpoint, subscription)
  values ('employer', v_emp, p_sub->>'endpoint', p_sub)
  on conflict (endpoint) do update set subscription = excluded.subscription;
end; $$;

-- worker (public, by public_id — demo-grade; tie to a session in prod)
create or replace function pub_save_push(p_public_id text, p_sub jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_worker uuid;
begin
  select id into v_worker from workers where public_id = p_public_id;
  if v_worker is null then raise exception 'NOT_FOUND'; end if;
  insert into push_subscriptions(actor_type, actor_id, endpoint, subscription)
  values ('worker', v_worker, p_sub->>'endpoint', p_sub)
  on conflict (endpoint) do update set subscription = excluded.subscription;
end; $$;

grant execute on function public.emp_save_push(text, jsonb) to anon, authenticated;
grant execute on function public.pub_save_push(text, jsonb) to anon, authenticated;
```
(Append to `full_setup.sql` via the regen script.)

### E. Edge Function `send-push` (Deno)
- `supabase functions new send-push`.
- Use a Deno Web Push lib (`import * as webpush from "jsr:@negrel/webpush"`), VAPID from `Deno.env`.
- Input: the inserted row (from the DB webhook). Look up `push_subscriptions` for that `worker_id` (+ relevant employer), build the message, send to each endpoint; delete subscriptions that return 404/410 (expired).
- Deploy + secrets:
```bash
supabase link --project-ref <ref>
supabase secrets set VAPID_PUBLIC_KEY=… VAPID_PRIVATE_KEY=… VAPID_SUBJECT=mailto:you@example.com
supabase functions deploy send-push --no-verify-jwt
```

### F. Wire the trigger (Supabase Dashboard → Database → Webhooks)
- New webhook on `wage_records` **INSERT** → HTTP POST → the `send-push` function URL, with a shared-secret header you verify inside the function.
- Repeat for `attendance_records` INSERT.
- Keep payloads **ASCII or guaranteed-UTF-8** (the notes' Hindi was mojibake). Example: `"Wage received: Rs.<amt> from <employer>"`, `"Attendance marked for <date>"`.

### G. QR onboarding moment (keep existing `QR` component)
Employer registers worker → passbook QR → worker (with smartphone) scans → passbook opens →
browser offers **Install app** → worker taps **Get wage alerts** → permission → `pub_save_push`.
For feature-phone workers this step simply doesn't apply — they stay on SMS.

### Phase-2 headers — `vercel.json`
Static files (incl. `sw.js`) are served before the SPA rewrite, so the SW loads fine. Add:
```json
{
  "rewrites": [{ "source": "/(.*)", "destination": "/index.html" }],
  "headers": [
    { "source": "/sw.js", "headers": [
      { "key": "Cache-Control", "value": "no-cache" },
      { "key": "Service-Worker-Allowed", "value": "/" }
    ]}
  ]
}
```

---

## Final pre-deploy checklist
- [ ] `git check-ignore .env.local` prints the filename (secret never committed)
- [ ] `npm run build` is green locally
- [ ] Vercel env vars set (URL, anon key, public base url) for **Production**
- [ ] `VITE_PUBLIC_BASE_URL` matches the live domain, then redeployed
- [ ] Live smoke test: login, offline sync, wage+trust, passbook tamper check, admin
- [ ] (Phase 2 only) VAPID public key in Vercel env; private key in Supabase secrets; `send-push` deployed; webhooks created; permission is button-triggered
- [ ] Pitch line ready: "Workers stay on SMS — push is an extra for those with smartphones."
