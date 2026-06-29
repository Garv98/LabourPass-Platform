import { useQuery } from '@tanstack/react-query'
import { BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, Tooltip, ResponsiveContainer, LineChart, Line } from 'recharts'
import { admin } from '../../lib/api'
import { Button, Card, Spinner, rupee } from '../../components/ui'
import { downloadCsv } from '../../lib/csv'
import { prettySkill } from '../../lib/constants'

const PIE = ['#0f766e', '#14b8a6', '#5eead4', '#0d9488', '#99f6e4', '#115e59', '#2dd4bf', '#134e4a']

export default function AdminAnalytics() {
  const { data, isLoading } = useQuery({ queryKey: ['admin-analytics'], queryFn: admin.wageAnalytics })
  const { data: index } = useQuery({ queryKey: ['admin-wage-index'], queryFn: admin.wageIndex })
  if (isLoading || !data) return <div className="flex justify-center py-16"><Spinner /></div>
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-ink">Wage & Workforce Analytics</h1>
        <Button variant="outline" onClick={() => downloadCsv('wages-by-state.csv', data.by_state as unknown as Record<string, unknown>[])}>⬇ CSV</Button>
      </div>

      {index && (
        <Card className="border-brand-200 bg-linear-to-br from-brand-50 to-white">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 className="font-semibold text-brand-800">📊 Live Informal Wage Index</h2>
              <p className="text-sm text-ink-soft">India has no real-time informal wage index. LabourPass generates one from ground-truth data.</p>
            </div>
            <div className="text-right">
              <span className="text-3xl font-extrabold text-brand-700">{rupee(index.overall_avg)}</span>
              <p className="text-xs text-ink-soft">avg daily wage</p>
            </div>
          </div>
          <ResponsiveContainer width="100%" height={200}>
            <BarChart data={index.by_skill.map((s) => ({ name: prettySkill(s.skill), wage: s.avg_wage }))}>
              <XAxis dataKey="name" fontSize={11} interval={0} angle={-20} textAnchor="end" height={50} />
              <YAxis fontSize={12} /><Tooltip formatter={(v) => rupee(v as number)} />
              <Bar dataKey="wage" fill="#0d9488" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <h2 className="mb-2 font-semibold text-ink">Wages by month</h2>
          <ResponsiveContainer width="100%" height={220}>
            <LineChart data={data.by_month}>
              <XAxis dataKey="month" fontSize={12} /><YAxis fontSize={12} /><Tooltip formatter={(v) => rupee(v as number)} />
              <Line type="monotone" dataKey="total" stroke="#0f766e" strokeWidth={2} />
            </LineChart>
          </ResponsiveContainer>
        </Card>

        <Card>
          <h2 className="mb-2 font-semibold text-ink">Wages by state</h2>
          <ResponsiveContainer width="100%" height={220}>
            <BarChart data={data.by_state}>
              <XAxis dataKey="state" fontSize={11} /><YAxis fontSize={12} /><Tooltip formatter={(v) => rupee(v as number)} />
              <Bar dataKey="total" fill="#0f766e" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>

        <Card className="lg:col-span-2">
          <h2 className="mb-2 font-semibold text-ink">Workforce by skill</h2>
          <ResponsiveContainer width="100%" height={260}>
            <PieChart>
              <Pie data={data.by_skill.map((s) => ({ name: prettySkill(s.skill), value: s.workers }))} dataKey="value" nameKey="name" outerRadius={100} label>
                {data.by_skill.map((_, i) => <Cell key={i} fill={PIE[i % PIE.length]} />)}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </Card>
      </div>
    </div>
  )
}
