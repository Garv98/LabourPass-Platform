import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { pub } from '../../lib/api'
import { Spinner } from '../../components/ui'
import { QR } from '../../components/QR'
import { Emblem } from '../../components/Emblem'
import { prettySkill } from '../../lib/constants'

export default function VerifyCertificate() {
  const { certNo } = useParams()
  const { data, isLoading } = useQuery({ queryKey: ['cert', certNo], queryFn: () => pub.verifyCertificate(certNo!) })

  if (isLoading)
    return (
      <div className="lp-paper flex min-h-full items-center justify-center"><Spinner /></div>
    )
  if (!data?.found)
    return (
      <div className="lp-paper flex min-h-full items-center justify-center px-4">
        <div className="lp-sheet max-w-md p-8 text-center">
          <p className="text-lg font-bold text-ink">प्रमाणपत्र नहीं मिला</p>
          <p className="mt-1 text-ink-soft">No certificate matches this number.</p>
          <Link to="/" className="mt-4 inline-block font-semibold text-band underline">घर जाएँ · Home</Link>
        </div>
      </div>
    )

  const c = data.certificate!
  return (
    <div className="lp-paper min-h-full py-8 print:py-0">
      <div className="mx-auto max-w-2xl px-4 print:px-0">
        <article className="lp-sheet print:border-0">
          <header className="lp-band relative px-6 py-5">
            <div className="flex items-start gap-3 pr-24">
              <span className="text-brand-100"><Emblem size={42} /></span>
              <div>
                <p className="text-[13px] font-semibold uppercase tracking-wider text-brand-200">LabourPass</p>
                <h1 className="text-2xl font-bold leading-tight text-[#fdfae9]">अनुभव प्रमाणपत्र</h1>
                <p className="text-sm text-brand-100">Experience Certificate</p>
              </div>
            </div>
            <div
              className="lp-stamp absolute right-5 top-5"
              style={{ color: data.valid ? '#ffd9cf' : '#ffd9cf', borderColor: data.valid ? '#ffd9cf' : '#ffd9cf' }}
            >
              {data.valid ? <>सत्यापित<br />Valid</> : <>निरस्त<br />Revoked</>}
            </div>
          </header>

          <section className="px-6 py-6">
            <p className="text-base text-ink-soft">यह प्रमाणित किया जाता है कि · This certifies that</p>
            <p className="mt-1 text-3xl font-bold text-ink">{c.worker_name}</p>
            <p className="font-mono text-base text-ink-soft">{c.worker_public_id}</p>

            <p className="mt-4 text-lg text-ink">
              ने <b>{c.employer_name}</b> के अधीन <b>{c.role}</b> के रूप में
              {c.worksite ? <> {c.worksite} पर</> : null} कार्य किया।
            </p>
            <p className="text-base text-ink-soft">
              worked as <b>{c.role}</b> for <b>{c.employer_name}</b>
              {c.worksite ? <> at {c.worksite}</> : null}.
            </p>

            <div className="mt-5 grid grid-cols-2 border-r border-b border-rule sm:grid-cols-3">
              <Cell hi="अवधि" en="Period" value={`${c.start_date} → ${c.end_date}`} />
              <Cell hi="कुल दिन" en="Total days" value={String(c.total_days)} />
              <Cell hi="प्रमाणपत्र सं." en="Certificate no." value={c.certificate_no} mono />
            </div>

            <div className="mt-4">
              <p className="text-base font-semibold text-ink">कौशल · Skills</p>
              <div className="mt-1 flex flex-wrap gap-2">
                {(c.skills ?? []).map((s) => (
                  <span key={s} className="border border-band bg-brand-50 px-2.5 py-0.5 text-sm font-semibold text-band-deep">{prettySkill(s)}</span>
                ))}
              </div>
            </div>

            {c.conduct && <p className="mt-4 border-l-4 border-rule bg-paper px-4 py-3 text-base text-ink">"{c.conduct}"</p>}
            {c.is_revoked && c.revoke_reason && <p className="mt-4 font-semibold text-stamp">निरस्त · Revoked: {c.revoke_reason}</p>}
          </section>

          <footer className="lp-band flex flex-wrap items-center justify-between gap-3 px-6 py-4">
            <div className="flex items-center gap-3">
              <div className="bg-white p-1"><QR value={window.location.href} size={72} /></div>
              <span className="text-sm text-brand-100">स्कैन कर सत्यापित करें<br />Scan to verify</span>
            </div>
            <button onClick={async () => { const { certificatePdf } = await import('../../lib/pdf'); await certificatePdf(data) }} className="min-h-12 border-2 border-brand-200 bg-[#fdfae9] px-4 font-semibold text-band-deep hover:bg-white lp-noprint">
              PDF
            </button>
          </footer>
        </article>
      </div>
    </div>
  )
}

function Cell({ hi, en, value, mono }: { hi: string; en: string; value: string; mono?: boolean }) {
  return (
    <div className="border-t border-l border-rule px-4 py-3">
      <div className="text-sm font-semibold text-ink-soft">{hi} · {en}</div>
      <div className={`text-base font-semibold text-ink ${mono ? 'font-mono' : ''}`}>{value}</div>
    </div>
  )
}
