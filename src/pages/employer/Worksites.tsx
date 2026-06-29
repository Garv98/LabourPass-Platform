import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { employer } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Field, Input, Spinner } from '../../components/ui'
import { Modal } from '../../components/Modal'

export default function Worksites() {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const { data, isLoading } = useQuery({ queryKey: ['worksites'], queryFn: employer.listWorksites })

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-ink">Worksites</h1>
        <Button onClick={() => setOpen(true)}>➕ Add Worksite</Button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !data?.length ? (
        <EmptyState title="No worksites" hint="Add a project/site to organise workers." />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {data.map((w) => (
            <Card key={w.id}>
              <div className="flex items-start justify-between">
                <h2 className="font-semibold text-ink">{w.name}</h2>
                {w.is_active ? <Badge color="green">Active</Badge> : <Badge>Archived</Badge>}
              </div>
              <p className="mt-1 text-sm text-ink-soft">{[w.district, w.state].filter(Boolean).join(', ') || '—'}</p>
              <p className="mt-2 text-sm text-ink-soft">👷 {w.worker_count ?? 0} workers</p>
            </Card>
          ))}
        </div>
      )}

      {open && <AddWorksite onClose={() => setOpen(false)} onSaved={() => { setOpen(false); qc.invalidateQueries({ queryKey: ['worksites'] }) }} />}
    </div>
  )
}

function AddWorksite({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const [form, setForm] = useState({ name: '', district: '', state: '', project_type: '' })
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }))
  const mut = useMutation({
    mutationFn: () => employer.createWorksite(form),
    onSuccess: () => { toast.success('Worksite added'); onSaved() },
    onError: (e) => toast.error((e as Error).message),
  })
  return (
    <Modal title="Add Worksite" onClose={onClose}>
      <div className="space-y-3">
        <Field label="Name *"><Input value={form.name} onChange={(e) => set('name', e.target.value)} /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="District"><Input value={form.district} onChange={(e) => set('district', e.target.value)} /></Field>
          <Field label="State"><Input value={form.state} onChange={(e) => set('state', e.target.value)} /></Field>
        </div>
        <Field label="Project Type"><Input value={form.project_type} onChange={(e) => set('project_type', e.target.value)} placeholder="commercial, residential…" /></Field>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={() => mut.mutate()} disabled={mut.isPending || !form.name}>Save</Button>
        </div>
      </div>
    </Modal>
  )
}
