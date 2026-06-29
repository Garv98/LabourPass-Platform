import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { admin } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Spinner } from '../../components/ui'

const STATUS_COLOR: Record<string, 'green' | 'amber' | 'red' | 'slate'> = {
  approved: 'green', pending: 'amber', suspended: 'red', rejected: 'slate',
}

export default function AdminEmployers() {
  const qc = useQueryClient()
  const { data, isLoading } = useQuery({ queryKey: ['admin-employers'], queryFn: () => admin.listEmployers() })

  const approve = useMutation({
    mutationFn: (id: string) => admin.approveEmployer(id),
    onSuccess: () => { toast.success('Employer approved — SMS sent'); qc.invalidateQueries({ queryKey: ['admin-employers'] }) },
    onError: (e) => toast.error((e as Error).message),
  })
  const suspend = useMutation({
    mutationFn: (id: string) => admin.suspendEmployer(id),
    onSuccess: () => { toast.success('Employer suspended'); qc.invalidateQueries({ queryKey: ['admin-employers'] }) },
    onError: (e) => toast.error((e as Error).message),
  })

  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-ink">Employers</h1>
      {!data?.length ? (
        <EmptyState title="No employers" />
      ) : (
        <div className="space-y-2">
          {data.map((e) => (
            <Card key={e.id} className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="font-semibold text-ink">{e.company_name || e.full_name}</p>
                <p className="text-sm text-ink-soft">📞 {e.phone} · {[e.district, e.state].filter(Boolean).join(', ') || '—'} · {e.total_workers} workers</p>
              </div>
              <div className="flex items-center gap-2">
                {e.trust_score != null && <Badge color={e.trust_score < 60 ? 'red' : 'green'}>{e.trust_score}%</Badge>}
                <Badge color={STATUS_COLOR[e.status]}>{e.status}</Badge>
                {e.status === 'pending' && <Button onClick={() => approve.mutate(e.id)} disabled={approve.isPending}>Approve</Button>}
                {e.status === 'approved' && <Button variant="danger" onClick={() => suspend.mutate(e.id)} disabled={suspend.isPending}>Suspend</Button>}
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
