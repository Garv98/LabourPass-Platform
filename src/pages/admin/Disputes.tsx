import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { admin } from '../../lib/api'
import type { Dispute } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Input, Spinner } from '../../components/ui'
import { downloadCsv } from '../../lib/csv'

const NEXT: Record<string, string[]> = {
  open: ['investigating', 'resolved', 'rejected'],
  investigating: ['resolved', 'rejected'],
  resolved: [],
  rejected: [],
}
const COLOR: Record<string, 'amber' | 'brand' | 'green' | 'slate'> = { open: 'amber', investigating: 'brand', resolved: 'green', rejected: 'slate' }

export default function AdminDisputes() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({ queryKey: ['disputes'], queryFn: () => admin.listDisputes() })

  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-ink">Disputes</h1>
        {!!data?.length && <Button variant="outline" onClick={() => downloadCsv('disputes.csv', data as unknown as Record<string, unknown>[])}>⬇ CSV</Button>}
      </div>
      {!data?.length ? (
        <EmptyState title="No disputes" hint="Worker-reported disputes appear here." />
      ) : (
        <div className="space-y-2">{data.map((d) => <DisputeRow key={d.id} d={d} onChanged={() => qc.invalidateQueries({ queryKey: ['disputes'] })} />)}</div>
      )}
    </div>
  )
}

function DisputeRow({ d, onChanged }: { d: Dispute; onChanged: () => void }) {
  const [notes, setNotes] = useState(d.resolution_notes ?? '')
  const mut = useMutation({
    mutationFn: (status: string) => admin.updateDispute(d.id, status, notes),
    onSuccess: () => { toast.success('Dispute updated'); onChanged() },
    onError: (e) => toast.error((e as Error).message),
  })
  return (
    <Card>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex items-center gap-2">
            <Badge color={COLOR[d.status]}>{d.status}</Badge>
            <Badge>{d.dispute_type}</Badge>
            <span className="text-xs text-ink-soft">{new Date(d.created_at).toLocaleString()}</span>
          </div>
          <p className="mt-1 font-medium text-ink">{d.worker_name} <span className="font-mono text-xs text-ink-soft">{d.public_id}</span></p>
          <p className="text-sm text-ink-soft">"{d.description}"</p>
          <p className="text-xs text-ink-soft">Employer: {d.employer_name || '—'}</p>
        </div>
      </div>
      {NEXT[d.status]?.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <Input placeholder="Resolution notes (sent to worker on resolve)" value={notes} onChange={(e) => setNotes(e.target.value)} className="max-w-md" />
          {NEXT[d.status].map((s) => (
            <Button key={s} variant={s === 'resolved' ? 'primary' : 'outline'} onClick={() => mut.mutate(s)} disabled={mut.isPending}>
              {s}
            </Button>
          ))}
        </div>
      )}
    </Card>
  )
}
