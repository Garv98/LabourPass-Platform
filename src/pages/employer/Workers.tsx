import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { employer } from '../../lib/api'
import type { Worksite } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Field, Input, Select, Spinner, rupee } from '../../components/ui'
import { Modal } from '../../components/Modal'
import { LANGUAGES, SKILLS, prettySkill } from '../../lib/constants'

export default function Workers() {
  const qc = useQueryClient()
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const { data: workers, isLoading } = useQuery({
    queryKey: ['workers', search],
    queryFn: () => employer.listWorkers(search || undefined),
  })
  const { data: worksites } = useQuery({ queryKey: ['worksites'], queryFn: employer.listWorksites })

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-ink">Workers</h1>
        <Button onClick={() => setOpen(true)}>➕ Register Worker</Button>
      </div>

      <Input placeholder="Search by name or phone…" value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-sm" />

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !workers?.length ? (
        <EmptyState title="No workers yet" hint="Register your first worker to begin." />
      ) : (
        <div className="overflow-x-auto rounded-xl border border-rule bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-paper text-ink-soft">
              <tr>
                <th className="px-4 py-2">Name</th>
                <th className="px-4 py-2">ID</th>
                <th className="px-4 py-2">Skills</th>
                <th className="px-4 py-2">Daily</th>
                <th className="px-4 py-2">Days (mo)</th>
                <th className="px-4 py-2">Last wage</th>
              </tr>
            </thead>
            <tbody>
              {workers.map((w) => (
                <tr key={w.id} className="border-t border-rule hover:bg-paper">
                  <td className="px-4 py-2 font-medium">
                    <Link to={`/employer/workers/${w.id}`} className="text-brand-700 hover:underline">{w.full_name}</Link>
                  </td>
                  <td className="px-4 py-2 font-mono text-xs text-ink-soft">{w.public_id}</td>
                  <td className="px-4 py-2">
                    <div className="flex flex-wrap gap-1">{w.skills?.map((s) => <Badge key={s}>{prettySkill(s)}</Badge>)}</div>
                  </td>
                  <td className="px-4 py-2">{w.daily_wage ? rupee(w.daily_wage) : '—'}</td>
                  <td className="px-4 py-2">{w.days_this_month}</td>
                  <td className="px-4 py-2 text-ink-soft">{w.last_wage_date ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {open && (
        <RegisterWorker
          worksites={worksites ?? []}
          onClose={() => setOpen(false)}
          onSaved={() => {
            setOpen(false)
            qc.invalidateQueries({ queryKey: ['workers'] })
          }}
        />
      )}
    </div>
  )
}

function RegisterWorker({ worksites, onClose, onSaved }: { worksites: Worksite[]; onClose: () => void; onSaved: () => void }) {
  const [form, setForm] = useState({
    full_name: '', phone: '', father_name: '', gender: 'male', aadhaar_last4: '',
    state: '', district: '', preferred_language: '', daily_wage: '', role_title: '',
    worksite_id: worksites[0]?.id ?? '',
  })
  const [skills, setSkills] = useState<string[]>([])
  const [channel, setChannel] = useState('both')
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }))
  const toggleSkill = (s: string) => setSkills((arr) => (arr.includes(s) ? arr.filter((x) => x !== s) : [...arr, s]))

  const mut = useMutation({
    mutationFn: async () => {
      const res = await employer.registerWorker({ ...form, skills, worksite_id: form.worksite_id || null })
      // best-effort: a channel-set failure must not fail the registration
      try {
        if (res?.worker?.id) await employer.setChannel(res.worker.id, channel)
      } catch {
        /* ignore */
      }
      return res
    },
    onSuccess: () => {
      toast.success('Worker registered — confirmation sent to their phone')
      onSaved()
    },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal title="Register New Worker" onClose={onClose}>
      <div className="space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <Field label="Full Name *"><Input value={form.full_name} onChange={(e) => set('full_name', e.target.value)} /></Field>
          <Field label="Mobile *"><Input value={form.phone} onChange={(e) => set('phone', e.target.value.replace(/\D/g, '').slice(0, 10))} inputMode="numeric" /></Field>
          <Field label="Father's Name"><Input value={form.father_name} onChange={(e) => set('father_name', e.target.value)} /></Field>
          <Field label="Gender">
            <Select value={form.gender} onChange={(e) => set('gender', e.target.value)}>
              <option value="male">Male</option><option value="female">Female</option><option value="other">Other</option>
            </Select>
          </Field>
          <Field label="State"><Input value={form.state} onChange={(e) => set('state', e.target.value)} /></Field>
          <Field label="District"><Input value={form.district} onChange={(e) => set('district', e.target.value)} /></Field>
          <Field label="Aadhaar (last 4)"><Input value={form.aadhaar_last4} onChange={(e) => set('aadhaar_last4', e.target.value.replace(/\D/g, '').slice(0, 4))} inputMode="numeric" /></Field>
          <Field label="Daily Wage (₹)"><Input value={form.daily_wage} onChange={(e) => set('daily_wage', e.target.value.replace(/\D/g, ''))} inputMode="numeric" /></Field>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Worksite">
            <Select value={form.worksite_id} onChange={(e) => set('worksite_id', e.target.value)}>
              <option value="">— none —</option>
              {worksites.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
            </Select>
          </Field>
          <Field label="Role"><Input value={form.role_title} onChange={(e) => set('role_title', e.target.value)} /></Field>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <Field label="SMS Language">
            <Select value={form.preferred_language} onChange={(e) => set('preferred_language', e.target.value)}>
              <option value="">Auto (by region / English)</option>
              {LANGUAGES.map((l) => <option key={l.code} value={l.code}>{l.label}</option>)}
            </Select>
          </Field>
          <Field label="Notify via">
            <Select value={channel} onChange={(e) => setChannel(e.target.value)}>
              <option value="both">SMS + WhatsApp</option>
              <option value="whatsapp">WhatsApp only</option>
              <option value="sms">SMS only</option>
              <option value="none">No messages</option>
            </Select>
          </Field>
        </div>

        <div>
          <span className="mb-1 block text-sm font-medium text-ink-soft">Skills</span>
          <div className="flex flex-wrap gap-2">
            {SKILLS.map((s) => (
              <button
                key={s}
                onClick={() => toggleSkill(s)}
                className={
                  'rounded-full border px-3 py-1 text-xs font-medium ' +
                  (skills.includes(s) ? 'border-brand-600 bg-brand-50 text-brand-800' : 'border-ink text-ink-soft')
                }
              >
                {prettySkill(s)}
              </button>
            ))}
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={() => mut.mutate()} disabled={mut.isPending || !form.full_name || form.phone.length !== 10}>
            Register Worker
          </Button>
        </div>
      </div>
    </Modal>
  )
}
