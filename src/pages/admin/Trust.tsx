import { useQuery } from '@tanstack/react-query'
import { admin } from '../../lib/api'
import { Badge, Card, EmptyState, Spinner } from '../../components/ui'

export default function AdminTrust() {
  const { data, isLoading } = useQuery({ queryKey: ['admin-trust'], queryFn: admin.trustScores })
  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-ink">Employer Trust Scores</h1>
      {!data?.length ? (
        <EmptyState title="No rated employers yet" />
      ) : (
        <div className="space-y-2">
          {data.map((e) => {
            const low = (e.trust_score ?? 100) < 60
            return (
              <Card key={e.id} className={low ? 'border-red-200 bg-red-50' : ''}>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="font-semibold text-ink">{e.company_name || e.full_name}</p>
                    <p className="text-xs text-ink-soft">{e.ratings} ratings</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={'text-xl font-bold ' + (low ? 'text-red-600' : 'text-green-600')}>{e.trust_score}%</span>
                    {low ? <Badge color="red">⚠ Investigate</Badge> : (e.trust_score ?? 0) >= 80 ? <Badge color="green">Verified Payer</Badge> : <Badge color="amber">Monitor</Badge>}
                  </div>
                </div>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
