import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { pub } from '../../lib/api'
import type { ChainVerify } from '../../lib/api'
import { Spinner, rupee } from '../../components/ui'
import { QR } from '../../components/QR'
import { Emblem } from '../../components/Emblem'
import { PushButton } from '../../components/PushButton'
import { passbookPdf } from '../../lib/pdf'
import { prettySkill } from '../../lib/constants'

export default function VerifyPassbook() {
  const { publicId } = useParams()
  const { data, isLoading } = useQuery({ queryKey: ['passbook', publicId], queryFn: () => pub.passbook(publicId!) })

  if (isLoading)
    return (
      <div className="lp-paper flex min-h-full items-center justify-center">
        <Spinner />
      </div>
    )

  if (!data?.found)
    return (
      <div className="lp-paper flex min-h-full items-center justify-center px-4">
        <div className="lp-sheet max-w-md p-8 text-center">
          <p className="text-lg font-bold text-ink">पुस्तिका नहीं मिली</p>
          <p className="mt-1 text-ink-soft">No passbook matches this number. Check the registration number and try again.</p>
          <Link to="/" className="mt-4 inline-block font-semibold text-band underline">घर जाएँ · Home</Link>
        </div>
      </div>
    )

  const w = data.worker!
  const s = data.summary!
  const url = window.location.href

  return (
    <div className="lp-paper min-h-full py-8 print:py-0">
      <div className="mx-auto max-w-3xl px-4 print:max-w-none print:px-0">
        <article className="lp-sheet print:border-0">
          {/* ── Cover band ───────────────────────────────────── */}
          <header className="lp-band relative px-6 py-5">
            <div className="flex items-start gap-3 pr-24">
              <span className="text-brand-100"><Emblem size={44} /></span>
              <div>
                <p className="text-[13px] font-semibold uppercase tracking-wider text-brand-200">LabourPass · असंगठित श्रमिक</p>
                <h1 className="text-2xl font-bold leading-tight text-[#fdfae9]">श्रमिक कार्य पुस्तिका</h1>
                <p className="text-sm text-brand-100">Worker Passbook</p>
              </div>
            </div>
            <div className="lp-stamp absolute right-5 top-5 text-[#ffd9cf]" style={{ borderColor: '#ffd9cf' }}>
              सत्यापित<br />Verified
            </div>
          </header>

          {/* ── Identity (ID-card row) ───────────────────────── */}
          <section className="flex flex-wrap items-start gap-5 border-b-2 border-ink px-6 py-5">
            <div className="flex h-28 w-22 items-center justify-center border-2 border-ink bg-paper text-4xl text-ink-soft" aria-hidden>
              👤
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold uppercase tracking-wide text-ink-soft">नाम · Name</p>
              <p className="text-2xl font-bold text-ink">{w.name}</p>

              <p className="mt-3 text-sm font-semibold uppercase tracking-wide text-ink-soft">पंजीकरण सं. · Registration no.</p>
              <div className="lp-serial mt-1" aria-label={`Registration number ${w.public_id}`}>
                {w.public_id.split('').map((ch, i) => (
                  <span key={i}>{ch}</span>
                ))}
              </div>

              <p className="mt-3 text-base text-ink">
                {[w.district, w.state].filter(Boolean).join(', ') || '—'}
                {w.skills.length > 0 && <> · {w.skills.map(prettySkill).join(' · ')}</>}
              </p>
            </div>
            <div className="flex flex-col items-center gap-1">
              <QR value={url} size={96} />
              <span className="text-xs font-semibold text-ink-soft">स्कैन करें · Scan to verify</span>
              <PushButton
                save={(sub) => pub.savePush(publicId!, sub)}
                label="Get wage alerts"
                className="lp-noprint mt-1 min-h-10 border-2 border-band bg-white px-2 text-sm font-semibold text-band hover:bg-paper disabled:opacity-60"
              />
            </div>
          </section>

          {/* ── Work summary ledger ──────────────────────────── */}
          <section className="px-6 py-5">
            <p className="lp-eyebrow">कार्य सारांश · Work summary</p>
            <div className="grid grid-cols-2 border-r border-b border-rule sm:grid-cols-4">
              <SummaryCell value={String(s.days_worked)} hi="कार्य दिवस" en="Days worked" tone="paid" />
              <SummaryCell value={rupee(s.total_wages)} hi="कुल वेतन" en="Total wages" />
              <SummaryCell value={String(s.employers)} hi="नियोक्ता" en="Employers" />
              <SummaryCell value={String(s.certificates)} hi="प्रमाणपत्र" en="Certificates" />
            </div>
          </section>

          <hr className="lp-perf" />

          {/* ── Wage ledger ──────────────────────────────────── */}
          <section className="px-6 py-5">
            <p className="lp-eyebrow">वेतन बही · Wage ledger</p>
            {!data.wages?.length ? (
              <p className="py-6 text-center text-ink-soft">कोई वेतन दर्ज नहीं · No wages recorded yet.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="lp-ledger">
                  <thead>
                    <tr>
                      <th>दिनांक · Date</th>
                      <th>राशि · Amount</th>
                      <th>माध्यम · Mode</th>
                      <th>नियोक्ता · Employer</th>
                      <th>स्थिति · Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.wages.map((g, i) => (
                      <tr key={i}>
                        <td className="font-mono">{g.payment_date}</td>
                        <td className="font-semibold">{rupee(g.amount)}</td>
                        <td className="capitalize">{g.mode.replace('_', ' ')}</td>
                        <td>{g.employer}</td>
                        <td><span className="lp-status text-paid">✓ भुगतान · Paid</span></td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </section>

          {/* ── Certificates ─────────────────────────────────── */}
          {!!data.certificates?.length && (
            <>
              <hr className="lp-perf" />
              <section className="px-6 py-5">
                <p className="lp-eyebrow">अनुभव प्रमाणपत्र · Experience certificates</p>
                {data.certificates.map((c) => (
                  <div key={c.certificate_no} className="flex flex-wrap items-center justify-between gap-2 border-b border-rule py-3 last:border-0">
                    <span className="font-semibold text-ink">{c.role_title}</span>
                    <span className="font-mono text-sm text-ink-soft">{c.start_date} → {c.end_date}</span>
                    <Link to={`/verify/cert/${c.certificate_no}`} className="font-mono text-sm font-semibold text-band underline">
                      {c.certificate_no}
                    </Link>
                  </div>
                ))}
              </section>
            </>
          )}

          <hr className="lp-perf" />

          {/* ── Record integrity (hash-chain) ────────────────── */}
          <section className="px-6 py-5">
            <ChainPanel publicId={publicId!} />
          </section>

          {/* ── Authenticity footer + actions ────────────────── */}
          <footer className="lp-band flex flex-wrap items-center justify-between gap-3 px-6 py-4">
            <p className="max-w-md text-sm text-brand-100">
              बैंक, कल्याण बोर्ड व नए नियोक्ता के साथ साझा करें। हर अभिलेख छेड़छाड़-रोधी है।<br />
              Share with banks, welfare boards and new employers. Every record is tamper-evident.
            </p>
            <div className="flex gap-2 lp-noprint">
              <button onClick={() => window.print()} className="min-h-12 border-2 border-brand-200 bg-transparent px-4 font-semibold text-[#fdfae9] hover:bg-band">
                प्रिंट · Print
              </button>
              <button onClick={() => passbookPdf(data)} className="min-h-12 border-2 border-brand-200 bg-[#fdfae9] px-4 font-semibold text-band-deep hover:bg-white">
                PDF
              </button>
            </div>
          </footer>
        </article>
      </div>
    </div>
  )
}

function SummaryCell({ value, hi, en, tone = 'ink' }: { value: string; hi: string; en: string; tone?: 'ink' | 'paid' }) {
  return (
    <div className="border-t border-l border-rule px-4 py-3">
      <div className={`text-3xl font-bold tabular-nums ${tone === 'paid' ? 'text-paid' : 'text-ink'}`}>{value}</div>
      <div className="mt-0.5 text-base font-semibold text-ink">{hi}</div>
      <div className="text-sm text-ink-soft">{en}</div>
    </div>
  )
}

function ChainPanel({ publicId }: { publicId: string }) {
  const qc = useQueryClient()
  const [result, setResult] = useState<ChainVerify | null>(null)
  const [busy, setBusy] = useState(false)
  const [showLedger, setShowLedger] = useState(false)
  const { data: ledger, refetch: refetchLedger } = useQuery({ queryKey: ['ledger', publicId], queryFn: () => pub.ledger(publicId) })

  async function verify() {
    setBusy(true)
    try {
      setResult(await pub.verifyChain(publicId))
      setShowLedger(true)
      refetchLedger()
    } finally {
      setBusy(false)
    }
  }

  async function tamper(restore: boolean) {
    await pub.demoTamper(publicId, restore)
    toast(restore ? 'Record restored' : 'Record altered in the database', { icon: restore ? '✓' : '⚠' })
    await Promise.all([refetchLedger(), verify()])
    qc.invalidateQueries({ queryKey: ['passbook', publicId] })
  }

  const intact = result && result.wage?.intact && result.attendance?.intact

  return (
    <div>
      <p className="lp-eyebrow">अभिलेख प्रमाणन · Record integrity</p>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="max-w-md text-base text-ink-soft">
          Every entry is sealed to the one before it with a SHA-256 hash. Re-check to confirm nothing has been changed.
        </p>
        <button
          onClick={verify}
          disabled={busy}
          className="min-h-12 border-2 border-ink bg-band px-5 font-semibold text-[#fdfae9] hover:bg-band-deep disabled:opacity-60"
        >
          {busy ? 'जाँच…' : 'जाँचें · Check records'}
        </button>
      </div>

      {result && (
        <div className="mt-3">
          {intact ? (
            <p className="border-2 border-paid bg-[#eaf4ec] px-4 py-3 text-base font-semibold text-paid">
              ✓ सुरक्षित · Verified — {result.wage?.total} wage and {result.attendance?.total} attendance records intact, untampered.
            </p>
          ) : (
            <p className="border-2 border-stamp bg-stamp-soft px-4 py-3 text-base font-semibold text-stamp">
              ✗ छेड़छाड़ · Tampering detected
              {result.wage && !result.wage.intact && ` — wage record #${result.wage.broken_at} was altered`}
              {result.attendance && !result.attendance.intact && ` — attendance record #${result.attendance.broken_at} was altered`}.
            </p>
          )}
        </div>
      )}

      {showLedger && ledger?.blocks && (
        <div className="mt-4">
          <p className="mb-2 text-sm font-semibold uppercase tracking-wide text-ink-soft">वेतन श्रृंखला · Linked wage records</p>
          <div className="flex gap-3 overflow-x-auto pb-2">
            {ledger.blocks.map((b) => (
              <div
                key={b.seq}
                className={'w-40 shrink-0 border-2 p-3 ' + (b.ok ? 'border-paid bg-[#eaf4ec]' : 'border-stamp bg-stamp-soft')}
              >
                <div className="flex items-center justify-between">
                  <span className="font-mono font-bold text-ink">#{b.seq}</span>
                  <span className={b.ok ? 'text-paid' : 'text-stamp'}>{b.ok ? '✓' : '✗'}</span>
                </div>
                <p className="mt-1 text-lg font-bold text-ink">{rupee(b.amount)}</p>
                <p className="font-mono text-xs text-ink-soft">{b.date}</p>
                <p className="mt-2 truncate font-mono text-[11px] text-ink-soft">↑ {b.prev}…</p>
                <p className="truncate font-mono text-[11px] text-band">● {b.hash}…</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Demo-only: prove tamper-evidence on stage without touching the database. */}
      <div className="lp-noprint mt-4 flex flex-wrap items-center gap-2 border-t border-rule pt-3">
        <span className="border border-ink bg-ink px-2 py-0.5 text-xs font-bold uppercase tracking-wide text-[#fdfae9]">Demo</span>
        <span className="text-sm text-ink-soft">See it work:</span>
        <button onClick={() => tamper(false)} className="min-h-12 border-2 border-stamp px-3 font-semibold text-stamp hover:bg-stamp-soft">
          Alter a record
        </button>
        <button onClick={() => tamper(true)} className="min-h-12 border-2 border-paid px-3 font-semibold text-paid hover:bg-[#eaf4ec]">
          Restore
        </button>
      </div>
    </div>
  )
}
