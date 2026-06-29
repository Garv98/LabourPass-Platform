import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { admin } from '../../lib/api'
import { Card, EmptyState, Input, Spinner, rupee } from '../../components/ui'
import { PUBLIC_BASE_URL } from '../../lib/supabase'

export default function AdminWorkers() {
  const [search, setSearch] = useState('')
  const { data, isLoading } = useQuery({ queryKey: ['admin-workers', search], queryFn: () => admin.listWorkers(search || undefined) })

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-ink">Workers</h1>
      <Input placeholder="Search name / phone / ID…" value={search} onChange={(e) => setSearch(e.target.value)} className="max-w-sm" />
      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !data?.length ? (
        <EmptyState title="No workers found" />
      ) : (
        <Card className="overflow-x-auto p-0">
          <table className="w-full text-left text-sm">
            <thead className="bg-paper text-ink-soft">
              <tr><th className="px-4 py-2">Name</th><th className="px-4 py-2">ID</th><th className="px-4 py-2">Phone</th><th className="px-4 py-2">State</th><th className="px-4 py-2">Employers</th><th className="px-4 py-2">Total wages</th><th className="px-4 py-2">Passbook</th></tr>
            </thead>
            <tbody>
              {data.map((w) => (
                <tr key={w.id} className="border-t border-rule">
                  <td className="px-4 py-2 font-medium">{w.full_name}</td>
                  <td className="px-4 py-2 font-mono text-xs">{w.public_id}</td>
                  <td className="px-4 py-2">{w.phone}</td>
                  <td className="px-4 py-2 text-ink-soft">{w.state || '—'}</td>
                  <td className="px-4 py-2">{w.employers}</td>
                  <td className="px-4 py-2">{rupee(w.total_wages)}</td>
                  <td className="px-4 py-2"><a className="text-brand-700 hover:underline" href={`${PUBLIC_BASE_URL}/verify/passbook/${w.public_id}`} target="_blank" rel="noreferrer">View ↗</a></td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  )
}
