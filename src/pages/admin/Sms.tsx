import { useQuery } from '@tanstack/react-query'
import { admin } from '../../lib/api'
import { Badge, Card, EmptyState, Spinner } from '../../components/ui'

export default function AdminSms() {
  const { data, isLoading } = useQuery({ queryKey: ['admin-sms'], queryFn: () => admin.smsLogs(150), refetchInterval: 4000 })
  if (isLoading) return <div className="flex justify-center py-16"><Spinner /></div>
  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-ink">SMS Logs <span className="text-sm font-normal text-ink-soft">(live)</span></h1>
      {!data?.length ? (
        <EmptyState title="No SMS yet" />
      ) : (
        <Card className="overflow-x-auto p-0">
          <table className="w-full text-left text-sm">
            <thead className="bg-paper text-ink-soft">
              <tr><th className="px-3 py-2">Time</th><th className="px-3 py-2">Dir</th><th className="px-3 py-2">Phone</th><th className="px-3 py-2">Message</th><th className="px-3 py-2">Type</th></tr>
            </thead>
            <tbody>
              {data.map((s, i) => (
                <tr key={i} className="border-t border-rule">
                  <td className="px-3 py-2 text-xs text-ink-soft">{new Date(s.created_at).toLocaleTimeString()}</td>
                  <td className="px-3 py-2">{s.direction === 'inbound' ? <Badge color="green">in</Badge> : <Badge color="slate">out</Badge>}</td>
                  <td className="px-3 py-2 font-mono text-xs">{s.phone}</td>
                  <td className="px-3 py-2 text-ink">{s.message}</td>
                  <td className="px-3 py-2 text-xs text-ink-soft">{s.reference_type}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  )
}
