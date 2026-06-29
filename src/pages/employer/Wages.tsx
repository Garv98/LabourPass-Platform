import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts'
import { employer } from '../../lib/api'
import type { WorkerRow } from '../../lib/api'
import { Badge, Button, Card, EmptyState, Field, Input, Select, Spinner, rupee } from '../../components/ui'
import { Modal } from '../../components/Modal'
import { PAYMENT_MODES } from '../../lib/constants'

export default function Wages() {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const { data: wages, isLoading } = useQuery({ queryKey: ['wages'], queryFn: employer.listWages })
  const { data: workers } = useQuery({ queryKey: ['workers', ''], queryFn: () => employer.listWorkers() })
  const { data: analytics } = useQuery({ queryKey: ['wage-analytics'], queryFn: employer.wageAnalytics })

  const trustMut = useMutation({
    mutationFn: (id: string) => employer.sendTrustSms(id),
    onSuccess: () => { toast.success('Trust rating SMS sent to worker'); qc.invalidateQueries({ queryKey: ['wages'] }) },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-ink">Wages</h1>
        <Button onClick={() => setOpen(true)}>💰 Record Wage</Button>
      </div>

      {analytics && analytics.by_month.length > 0 && (
        <Card>
          <div className="mb-2 flex items-center justify-between">
            <h2 className="font-semibold text-ink">Wage disbursement</h2>
            <span className="text-sm text-ink-soft">Total {rupee(analytics.total_disbursed)}</span>
          </div>
          <ResponsiveContainer width="100%" height={180}>
            <BarChart data={analytics.by_month}>
              <XAxis dataKey="month" fontSize={12} />
              <YAxis fontSize={12} />
              <Tooltip formatter={(v) => rupee(v as number)} />
              <Bar dataKey="total" fill="#0f766e" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </Card>
      )}

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !wages?.length ? (
        <EmptyState title="No wages recorded" hint="Record a wage to generate an SMS receipt." />
      ) : (
        <div className="overflow-x-auto rounded-xl border border-rule bg-white">
          <table className="w-full text-left text-sm">
            <thead className="bg-paper text-ink-soft">
              <tr><th className="px-4 py-2">Date</th><th className="px-4 py-2">Worker</th><th className="px-4 py-2">Amount</th><th className="px-4 py-2">Mode</th><th className="px-4 py-2">Ref</th><th className="px-4 py-2">Trust</th></tr>
            </thead>
            <tbody>
              {wages.map((g) => (
                <tr key={g.id} className="border-t border-rule">
                  <td className="px-4 py-2">{g.payment_date}</td>
                  <td className="px-4 py-2 font-medium">{g.worker_name}</td>
                  <td className="px-4 py-2">{rupee(g.amount)}</td>
                  <td className="px-4 py-2 text-ink-soft">{g.payment_mode}</td>
                  <td className="px-4 py-2 font-mono text-xs text-ink-soft">{g.reference_no}</td>
                  <td className="px-4 py-2">
                    {g.trust_sms_sent ? (
                      <Badge color="slate">sent</Badge>
                    ) : (
                      <button onClick={() => trustMut.mutate(g.id)} disabled={trustMut.isPending} className="text-xs font-semibold text-brand-700 hover:underline">
                        Send trust SMS
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {open && <RecordWage workers={workers ?? []} onClose={() => setOpen(false)} onSaved={() => { setOpen(false); qc.invalidateQueries({ queryKey: ['wages'] }); qc.invalidateQueries({ queryKey: ['wage-analytics'] }) }} />}
    </div>
  )
}

function RecordWage({ workers, onClose, onSaved }: { workers: WorkerRow[]; onClose: () => void; onSaved: () => void }) {
  const today = new Date().toISOString().slice(0, 10)
  const [workerId, setWorkerId] = useState(workers[0]?.id ?? '')
  const [form, setForm] = useState({ payment_date: today, amount: '', payment_mode: 'cash', period_from: '', period_to: '', days_covered: '', reference_no: '', notes: '' })
  const set = (k: string, v: string) => setForm((f) => ({ ...f, [k]: v }))
  const worker = useMemo(() => workers.find((w) => w.id === workerId), [workers, workerId])

  const mut = useMutation({
    mutationFn: () =>
      employer.recordWage({
        worker_id: workerId,
        engagement_id: worker?.engagement_id,
        ...form,
        idempotency_key: `${worker?.engagement_id}|${form.payment_date}|${form.amount}`,
      }),
    onSuccess: () => { toast.success('Wage recorded — receipt SMS sent'); onSaved() },
    onError: (e) => toast.error((e as Error).message),
  })

  return (
    <Modal title="Record Wage Payment" onClose={onClose}>
      <div className="space-y-3">
        <Field label="Worker *">
          <Select value={workerId} onChange={(e) => setWorkerId(e.target.value)}>
            {workers.map((w) => <option key={w.id} value={w.id}>{w.full_name} ({w.public_id})</option>)}
          </Select>
        </Field>
        {worker && (
          <p className="rounded-lg bg-paper px-3 py-2 text-sm text-ink-soft">
            Daily ₹{worker.daily_wage ?? '—'} · {worker.days_this_month} days this month
            {worker.daily_wage ? ` · expected ${rupee((worker.daily_wage ?? 0) * worker.days_this_month)}` : ''}
          </p>
        )}
        <div className="grid grid-cols-2 gap-3">
          <Field label="Payment Date *"><Input type="date" value={form.payment_date} max={today} onChange={(e) => set('payment_date', e.target.value)} /></Field>
          <Field label="Amount (₹) *"><Input value={form.amount} onChange={(e) => set('amount', e.target.value.replace(/[^\d.]/g, ''))} inputMode="decimal" /></Field>
          <Field label="Mode">
            <Select value={form.payment_mode} onChange={(e) => set('payment_mode', e.target.value)}>
              {PAYMENT_MODES.map((m) => <option key={m} value={m}>{m}</option>)}
            </Select>
          </Field>
          <Field label="Days Covered"><Input value={form.days_covered} onChange={(e) => set('days_covered', e.target.value.replace(/\D/g, ''))} inputMode="numeric" /></Field>
          <Field label="Period From"><Input type="date" value={form.period_from} onChange={(e) => set('period_from', e.target.value)} /></Field>
          <Field label="Period To"><Input type="date" value={form.period_to} onChange={(e) => set('period_to', e.target.value)} /></Field>
        </div>
        <Field label="Reference / UPI No."><Input value={form.reference_no} onChange={(e) => set('reference_no', e.target.value)} /></Field>
        <p className="text-xs text-ink-soft">Worker receives an SMS receipt immediately. Send the trust-rating SMS from the wages list afterwards.</p>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="outline" onClick={onClose}>Cancel</Button>
          <Button onClick={() => mut.mutate()} disabled={mut.isPending || !workerId || !form.amount}>Record Payment</Button>
        </div>
      </div>
    </Modal>
  )
}
