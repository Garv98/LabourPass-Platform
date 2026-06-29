import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { useLiveQuery } from 'dexie-react-hooks'
import toast from 'react-hot-toast'
import { employer } from '../../lib/api'
import type { Employer } from '../../lib/api'
import { db } from '../../lib/offline'
import { Button, Field, Input, Spinner, rupee } from '../../components/ui'
import { Modal } from '../../components/Modal'
import { Emblem } from '../../components/Emblem'
import { PushButton } from '../../components/PushButton'
import { useOnline } from '../../lib/useOnline'
import { setSession } from '../../lib/session'

export default function EmployerDashboard() {
  const online = useOnline()
  const qc = useQueryClient()
  const [editProfile, setEditProfile] = useState(false)
  const pending = useLiveQuery(() => db.attendanceQueue.where('synced').equals(0).count(), [], 0)
  const { data, isLoading } = useQuery({ queryKey: ['emp-me'], queryFn: employer.me, refetchInterval: 5000 })
  const { data: activity } = useQuery({ queryKey: ['emp-activity'], queryFn: employer.recentActivity, refetchInterval: 5000 })
  const { data: alerts } = useQuery({ queryKey: ['emp-alerts'], queryFn: employer.alerts })

  if (isLoading)
    return (
      <div className="flex justify-center py-20">
        <Spinner />
      </div>
    )

  const stats = data?.stats
  const e = data?.employer
  const score = stats?.trust_score
  const needsProfile = e && (!e.company_name || e.full_name?.startsWith('Employer '))

  return (
    <div className="lp-paper -mx-4 -my-6 min-h-full space-y-5 px-4 py-6 sm:px-6">
      {/* ── Masthead: contractor register cover ───────────────── */}
      <div className="lp-sheet">
        <div className="lp-band flex flex-wrap items-start justify-between gap-3 px-5 py-4">
          <div className="flex items-start gap-3">
            <span className="text-brand-100"><Emblem size={40} /></span>
            <div>
              <p className="text-[13px] font-semibold uppercase tracking-wider text-brand-200">श्रमिक पास · ठेकेदार पंजी</p>
              <h1 className="text-2xl font-bold leading-tight text-[#fdfae9]">{e?.company_name || e?.full_name}</h1>
              <p className="text-sm text-brand-100">Contractor register · {e?.phone}</p>
            </div>
          </div>
          {score != null && score >= 80 && (
            <div className="lp-stamp bg-[#fffdf6]/0 text-[#ffd9cf]" style={{ borderColor: '#ffd9cf' }}>
              सत्यापित<br />Verified payer
            </div>
          )}
        </div>

        {/* status strip — icon + word + colour, never colour alone */}
        <div className="flex flex-wrap items-center gap-x-5 gap-y-1 border-t-2 border-rule px-5 py-3">
          {online ? (
            <span className="lp-status text-paid">● ऑनलाइन / Online</span>
          ) : (
            <span className="lp-status text-amber-ink">○ ऑफ़लाइन / Offline — entries will sync later</span>
          )}
          {pending! > 0 && <span className="lp-status text-stamp">⟳ {pending} बाकी / waiting to sync</span>}
          <PushButton save={employer.savePush} label="Enable alerts" className="ml-auto min-h-10 border-2 border-band bg-white px-3 text-sm font-semibold text-band hover:bg-paper disabled:opacity-60" />
        </div>
      </div>

      {needsProfile && (
        <div className="lp-sheet flex flex-wrap items-center justify-between gap-3 px-5 py-4">
          <div>
            <p className="text-lg font-semibold text-ink">अपनी जानकारी पूरी करें</p>
            <p className="text-sm text-ink-soft">Add your business name so it appears on workers' wage receipts and certificates.</p>
          </div>
          <Button onClick={() => setEditProfile(true)}>Complete profile</Button>
        </div>
      )}

      {/* ── Today's work: biggest actions, always above the fold ── */}
      <section>
        <p className="lp-eyebrow">आज का काम · Today's work</p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Link to="/employer/attendance" className="lp-action lp-action--primary">
            <span className="text-3xl" aria-hidden>✓</span>
            <span>
              <span className="block text-xl font-bold">हाज़िरी लगाएं</span>
              <span className="block text-sm opacity-90">Mark attendance</span>
            </span>
          </Link>
          <Link to="/employer/wages" className="lp-action lp-action--primary">
            <span className="text-3xl" aria-hidden>₹</span>
            <span>
              <span className="block text-xl font-bold">वेतन दर्ज करें</span>
              <span className="block text-sm opacity-90">Record wage payment</span>
            </span>
          </Link>
        </div>
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <Link to="/employer/workers" className="lp-action">
            <span className="text-2xl" aria-hidden>＋</span>
            <span><span className="block text-lg font-semibold">मज़दूर जोड़ें</span><span className="block text-sm text-ink-soft">Add a worker</span></span>
          </Link>
          <Link to="/employer/certificates" className="lp-action">
            <span className="text-2xl" aria-hidden>▣</span>
            <span><span className="block text-lg font-semibold">प्रमाणपत्र दें</span><span className="block text-sm text-ink-soft">Issue certificate</span></span>
          </Link>
        </div>
      </section>

      {/* ── Account summary: muster-roll ledger strip ──────────── */}
      <section className="lp-sheet p-5">
        <p className="lp-eyebrow">खाता सारांश · Account summary</p>
        <div className="grid grid-cols-2 border-r border-b border-rule sm:grid-cols-4">
          <LedgerCell value={String(stats?.total_workers ?? 0)} hi="मज़दूर" en="Workers" />
          <LedgerCell value={String(stats?.active_today ?? 0)} hi="आज हाज़िर" en="Present today" tone="paid" />
          <LedgerCell value={rupee(stats?.month_wages)} hi="इस माह वेतन" en="Wages this month" />
          <LedgerCell
            value={score != null ? `${score}%` : '—'}
            hi="भरोसा स्कोर"
            en={score == null ? 'No ratings yet' : score >= 80 ? '✓ Verified payer' : score < 60 ? '⚠ Under review' : 'Monitoring'}
            tone={score != null && score < 60 ? 'stamp' : score != null && score >= 80 ? 'paid' : 'ink'}
          />
        </div>
      </section>

      {/* ── Unpaid-wage alert: red rubber-stamp box ────────────── */}
      {alerts && alerts.unpaid.length > 0 && (
        <section className="lp-sheet border-stamp" style={{ background: 'var(--color-stamp-soft)' }}>
          <div className="border-b-2 border-stamp px-5 py-3">
            <p className="text-lg font-bold text-stamp">⚠ बकाया वेतन · Wages overdue</p>
            <p className="text-sm text-ink-soft">{alerts.unpaid.length} worker(s) have worked recently but haven't been paid in over 15 days. Pay them to protect your trust score.</p>
          </div>
          <ul>
            {alerts.unpaid.map((u) => (
              <li key={u.id} className="flex flex-wrap items-center justify-between gap-2 border-b border-rule px-5 py-3 last:border-0">
                <span className="font-semibold text-ink">{u.full_name} <span className="font-mono text-sm text-ink-soft">{u.public_id}</span></span>
                <span className="text-sm text-ink-soft">{u.recent_days} days worked · last paid {u.last_paid ?? 'never'}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ── Recent entries: ruled ledger ──────────────────────── */}
      <section className="lp-sheet p-5">
        <p className="lp-eyebrow">हाल की प्रविष्टियाँ · Recent entries</p>
        {!activity?.length ? (
          <div className="py-8 text-center">
            <p className="text-lg font-semibold text-ink">अभी कोई प्रविष्टि नहीं</p>
            <p className="mt-1 text-sm text-ink-soft">No entries yet. Mark attendance or record a wage to begin your register.</p>
          </div>
        ) : (
          <ul>
            {activity.map((a, i) => (
              <li key={i} className="flex items-center gap-3 border-b border-rule py-3 last:border-0">
                <span className="text-lg" aria-hidden>{a.type === 'wage' ? '₹' : a.type === 'attendance' ? '✓' : '▣'}</span>
                <span className="flex-1 text-base text-ink">{a.label}</span>
                <span className="font-mono text-sm text-ink-soft">{new Date(a.event_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      {editProfile && e && (
        <ProfileModal employer={e} onClose={() => setEditProfile(false)} onSaved={() => { setEditProfile(false); qc.invalidateQueries({ queryKey: ['emp-me'] }) }} />
      )}
    </div>
  )
}

function LedgerCell({ value, hi, en, tone = 'ink' }: { value: string; hi: string; en: string; tone?: 'ink' | 'paid' | 'stamp' }) {
  const color = tone === 'paid' ? 'text-paid' : tone === 'stamp' ? 'text-stamp' : 'text-ink'
  return (
    <div className="border-t border-l border-rule px-4 py-3">
      <div className={`text-3xl font-bold tabular-nums ${color}`}>{value}</div>
      <div className="mt-0.5 text-base font-semibold text-ink">{hi}</div>
      <div className="text-sm text-ink-soft">{en}</div>
    </div>
  )
}

function ProfileModal({ employer: e, onClose, onSaved }: { employer: Employer; onClose: () => void; onSaved: () => void }) {
  const [form, setForm] = useState({
    full_name: e.full_name?.startsWith('Employer ') ? '' : e.full_name ?? '',
    company_name: e.company_name ?? '',
    business_type: e.business_type ?? '',
    district: e.district ?? '',
    state: e.state ?? '',
  })
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }))
  const mut = useMutation({
    mutationFn: () => employer.updateProfile(form),
    onSuccess: (updated) => {
      const token = localStorage.getItem('lp_token')!
      setSession(token, 'employer', updated)
      toast.success('Profile updated')
      onSaved()
    },
    onError: (err) => toast.error((err as Error).message),
  })
  return (
    <Modal title="Business Profile" onClose={onClose}>
      <div className="space-y-3">
        <Field label="Your Name"><Input value={form.full_name} onChange={(ev) => set('full_name', ev.target.value)} /></Field>
        <Field label="Company / Business Name"><Input value={form.company_name} onChange={(ev) => set('company_name', ev.target.value)} /></Field>
        <Field label="Business Type"><Input value={form.business_type} onChange={(ev) => set('business_type', ev.target.value)} placeholder="construction, farm, household…" /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="District"><Input value={form.district} onChange={(ev) => set('district', ev.target.value)} /></Field>
          <Field label="State"><Input value={form.state} onChange={(ev) => set('state', ev.target.value)} /></Field>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={() => mut.mutate()} disabled={mut.isPending}>Save</Button>
        </div>
      </div>
    </Modal>
  )
}
