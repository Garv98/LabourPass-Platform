import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { employer, pub } from '../../lib/api'
import { Badge, Button, Card, Spinner, rupee } from '../../components/ui'
import { QR } from '../../components/QR'
import { PUBLIC_BASE_URL } from '../../lib/supabase'
import { prettySkill } from '../../lib/constants'

const STATUS_CLR: Record<string, string> = {
  present: 'bg-green-500', half_day: 'bg-amber-400', absent: 'bg-red-400', paid_leave: 'bg-blue-400',
}

export default function WorkerDetail() {
  const { id } = useParams()
  const { data, isLoading } = useQuery({ queryKey: ['worker', id], queryFn: () => employer.workerDetail(id!) })
  const [downloading, setDownloading] = useState(false)

  if (isLoading || !data) return <div className="flex justify-center py-16"><Spinner /></div>

  const w = data.worker
  const link = `${PUBLIC_BASE_URL}/verify/passbook/${w.public_id}`

  async function downloadPdf() {
    setDownloading(true)
    try {
      const pb = await pub.passbook(w.public_id as string)
      const { passbookPdf } = await import('../../lib/pdf')
      await passbookPdf(pb)
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setDownloading(false)
    }
  }

  return (
    <div className="space-y-5">
      <Link to="/employer/workers" className="text-sm text-ink-soft">← Workers</Link>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-ink">{w.full_name}</h1>
          <p className="text-sm text-ink-soft">{w.public_id} · 📞 {w.phone}</p>
          <div className="mt-2 flex flex-wrap gap-1">{data.skills.map((s) => <Badge key={s} color="brand">{prettySkill(s)}</Badge>)}</div>
        </div>
        <div className="flex items-center gap-3">
          <QR value={link} size={96} />
          <div className="flex flex-col gap-2">
            <Button variant="outline" onClick={() => { navigator.clipboard.writeText(link); toast.success('Passbook link copied') }}>🔗 Share Link</Button>
            <Button onClick={downloadPdf} disabled={downloading}>⬇ PDF</Button>
          </div>
        </div>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Card>
          <h2 className="mb-3 font-semibold text-ink">Attendance (last 90 days)</h2>
          <div className="flex flex-wrap gap-1">
            {data.attendance.length === 0 && <span className="text-sm text-ink-soft">No records</span>}
            {data.attendance.map((a, i) => (
              <span key={i} title={`${a.attendance_date} · ${a.status}`} className={`h-4 w-4 rounded-sm ${STATUS_CLR[a.status] ?? 'bg-slate-200'}`} />
            ))}
          </div>
          <div className="mt-3 flex gap-3 text-xs text-ink-soft">
            <span>🟩 Present</span><span>🟨 Half</span><span>🟥 Absent</span>
          </div>
        </Card>

        <Card>
          <h2 className="mb-3 font-semibold text-ink">Wage History</h2>
          <table className="w-full text-left text-sm">
            <tbody>
              {data.wages.map((g) => (
                <tr key={g.id} className="border-b border-rule">
                  <td className="py-1.5">{g.payment_date}</td>
                  <td className="py-1.5 font-medium">{rupee(g.amount)}</td>
                  <td className="py-1.5 text-ink-soft">{g.payment_mode}</td>
                  <td className="py-1.5 text-ink-soft">{g.employer_name}</td>
                </tr>
              ))}
              {data.wages.length === 0 && <tr><td className="py-2 text-ink-soft">No wages</td></tr>}
            </tbody>
          </table>
        </Card>
      </div>

      {data.certificates.length > 0 && (
        <Card>
          <h2 className="mb-3 font-semibold text-ink">Certificates</h2>
          {data.certificates.map((c) => (
            <div key={c.certificate_no} className="flex items-center justify-between border-b border-rule py-2 text-sm">
              <span className="font-mono text-xs">{c.certificate_no}</span>
              <span>{c.role_title}</span>
              <span className="text-ink-soft">{c.start_date} → {c.end_date}</span>
              {c.is_revoked ? <Badge color="red">Revoked</Badge> : <Badge color="green">Valid</Badge>}
            </div>
          ))}
        </Card>
      )}
    </div>
  )
}
