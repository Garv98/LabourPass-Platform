import { useQuery } from '@tanstack/react-query'
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { employer } from '../../lib/api'
import { Badge, Card, EmptyState, Spinner, StatCard } from '../../components/ui'

export default function Trust() {
  const { data, isLoading } = useQuery({ queryKey: ['trust'], queryFn: employer.trustSummary })
  if (isLoading || !data) return <div className="flex justify-center py-16"><Spinner /></div>

  const score = data.score
  const badge =
    score == null ? null : score >= 80 ? <Badge color="green">✓ Verified Payer</Badge> : score < 60 ? <Badge color="red">⚠ Under review</Badge> : <Badge color="amber">Monitoring</Badge>

  return (
    <div className="space-y-5">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-ink">Trust Score</h1>
        {badge}
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Current Score" value={score != null ? `${score}%` : '—'} accent={score != null && score < 60 ? 'text-red-600' : 'text-brand-700'} />
        <StatCard label="Total Ratings" value={data.total_ratings} />
        <StatCard label="Positive" value={data.positive} accent="text-green-600" />
        <StatCard label="Negative" value={data.negative} accent="text-red-600" />
      </div>

      <Card>
        <h2 className="mb-2 font-semibold text-ink">Score trend</h2>
        {data.trend.length === 0 ? (
          <EmptyState title="No rated payments yet" hint="Workers rate payments via a single SMS reply." />
        ) : (
          <ResponsiveContainer width="100%" height={200}>
            <LineChart data={data.trend}>
              <XAxis dataKey="month" fontSize={12} />
              <YAxis domain={[0, 100]} fontSize={12} />
              <Tooltip />
              <Line type="monotone" dataKey="score" stroke="#0f766e" strokeWidth={2} dot />
            </LineChart>
          </ResponsiveContainer>
        )}
      </Card>

      <Card>
        <h2 className="mb-2 font-semibold text-ink">Recent ratings</h2>
        {data.recent.length === 0 ? (
          <p className="text-sm text-ink-soft">No responses yet.</p>
        ) : (
          <table className="w-full text-left text-sm">
            <tbody>
              {data.recent.map((r, i) => (
                <tr key={i} className="border-b border-rule">
                  <td className="py-2 text-ink-soft">{r.date}</td>
                  <td className="py-2 font-mono">{r.worker}</td>
                  <td className="py-2">{r.rating === 1 ? <Badge color="green">Paid in full</Badge> : <Badge color="red">Not paid / partial</Badge>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>

      {score != null && score < 60 && (
        <Card className="border-red-200 bg-red-50">
          <p className="text-sm text-red-700">Your score is below 60%. Pay workers fully and on time to recover. Persistent low scores trigger admin review.</p>
        </Card>
      )}
    </div>
  )
}
