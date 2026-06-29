import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { employer } from '../../lib/api'
import type { WorkerRow } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Field, Input, Select, Spinner } from '../../components/ui'
import { Modal } from '../../components/Modal'
import { SKILLS, prettySkill } from '../../lib/constants'

export default function Certificates() {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const { data: certs, isLoading } = useQuery({ queryKey: ['certs'], queryFn: employer.listCertificates })
  const { data: workers } = useQuery({ queryKey: ['workers', ''], queryFn: () => employer.listWorkers() })

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-ink">Experience Certificates</h1>
        <Button onClick={() => setOpen(true)}>📜 Issue Certificate</Button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !certs?.length ? (
        <EmptyState title="No certificates issued" hint="Issue a certificate after a project completes." />
      ) : (
        <div className="space-y-2">
          {certs.map((c) => (
            <Card key={c.certificate_no} className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="font-semibold text-ink">{c.worker_name} — {c.role_title}</p>
                <p className="font-mono text-xs text-ink-soft">{c.certificate_no} · {c.start_date} → {c.end_date}</p>
              </div>
              <div className="flex items-center gap-2">
                {c.is_revoked ? <Badge color="red">Revoked</Badge> : <Badge color="green">Valid</Badge>}
                <a className="text-sm font-semibold text-brand-700 hover:underline" href={`/verify/cert/${c.certificate_no}`} target="_blank" rel="noreferrer">Verify ↗</a>
              </div>
            </Card>
          ))}
        </div>
      )}

      {open && <IssueCert workers={workers ?? []} onClose={() => setOpen(false)} onSaved={() => { setOpen(false); qc.invalidateQueries({ queryKey: ['certs'] }) }} />}
    </div>
  )
}

function IssueCert({ workers, onClose, onSaved }: { workers: WorkerRow[]; onClose: () => void; onSaved: () => void }) {
  const today = new Date().toISOString().slice(0, 10)
  const [workerId, setWorkerId] = useState(workers[0]?.id ?? '')
  const [form, setForm] = useState({ role_title: '', worksite_name: '', start_date: '', end_date: today, conduct_remarks: '', issued_by: '' })
  const [skills, setSkills] = useState<string[]>([])
  const worker = workers.find((w) => w.id === workerId)
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }))
  const toggle = (s: string) => setSkills((a) => (a.includes(s) ? a.filter((x) => x !== s) : [...a, s]))

  const mut = useMutation({
    mutationFn: () => employer.issueCertificate({ worker_id: workerId, engagement_id: worker?.engagement_id, ...form, skills }),
    onSuccess: () => { toast.success('Certificate issued — SMS sent'); onSaved() },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal title="Issue Experience Certificate" onClose={onClose}>
      <div className="space-y-3">
        <Field label="Worker *">
          <Select value={workerId} onChange={(e) => setWorkerId(e.target.value)}>
            {workers.map((w) => <option key={w.id} value={w.id}>{w.full_name} ({w.public_id})</option>)}
          </Select>
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="Role *"><Input value={form.role_title} onChange={(e) => set('role_title', e.target.value)} /></Field>
          <Field label="Worksite"><Input value={form.worksite_name} onChange={(e) => set('worksite_name', e.target.value)} /></Field>
          <Field label="Start Date *"><Input type="date" value={form.start_date} onChange={(e) => set('start_date', e.target.value)} /></Field>
          <Field label="End Date *"><Input type="date" value={form.end_date} onChange={(e) => set('end_date', e.target.value)} /></Field>
          <Field label="Issued By"><Input value={form.issued_by} onChange={(e) => set('issued_by', e.target.value)} /></Field>
        </div>
        <Field label="Conduct Remarks"><Input value={form.conduct_remarks} onChange={(e) => set('conduct_remarks', e.target.value)} /></Field>
        <div>
          <span className="mb-1 block text-sm font-medium text-ink-soft">Skills Demonstrated</span>
          <div className="flex flex-wrap gap-2">
            {SKILLS.slice(0, 8).map((s) => (
              <button key={s} onClick={() => toggle(s)} className={'rounded-full border px-3 py-1 text-xs ' + (skills.includes(s) ? 'border-brand-600 bg-brand-50 text-brand-800' : 'border-ink text-ink-soft')}>
                {prettySkill(s)}
              </button>
            ))}
          </div>
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={() => mut.mutate()} disabled={mut.isPending || !workerId || !form.role_title || !form.start_date}>Issue</Button>
        </div>
      </div>
    </Modal>
  )
}
