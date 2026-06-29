import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { admin } from '../../lib/api'
import { Card, Spinner, StatCard, rupee } from '../../components/ui'

export default function AdminDashboard() {
  const { data, isLoading } = useQuery({ queryKey: ['admin-dash'], queryFn: admin.dashboard, refetchInterval: 5000 })
  if (isLoading || !data) return <div className="flex justify-center py-20"><Spinner /></div>
  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold text-ink">Platform Overview</h1>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatCard label="Workers" value={data.workers} />
        <StatCard label="Employers" value={data.employers} />
        <StatCard label="Wages Disbursed" value={rupee(data.wages_total)} accent="text-brand-700" />
        <StatCard label="Certificates" value={data.certificates} />
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <Alert to="/admin/employers" label="Pending Approvals" value={data.pending_employers} color="amber" />
        <Alert to="/admin/disputes" label="Open Disputes" value={data.open_disputes} color="red" />
        <Alert to="/admin/trust" label="Low Trust Employers" value={data.low_trust} color="red" />
      </div>
    </div>
  )
}

function Alert({ to, label, value, color }: { to: string; label: string; value: number; color: 'amber' | 'red' }) {
  return (
    <Link to={to}>
      <Card className={value > 0 ? (color === 'red' ? 'border-red-200 bg-red-50' : 'border-amber-200 bg-amber-50') : ''}>
        <span className="text-sm text-ink-soft">{label}</span>
        <div className={'mt-1 text-2xl font-bold ' + (value > 0 ? (color === 'red' ? 'text-red-600' : 'text-amber-600') : 'text-ink')}>{value}</div>
      </Card>
    </Link>
  )
}
