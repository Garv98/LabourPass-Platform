import { useEffect, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useLiveQuery } from 'dexie-react-hooks'
import toast from 'react-hot-toast'
import { useTranslation } from 'react-i18next'
import { clsx } from 'clsx'
import { employer } from '../../lib/api'
import { db, flushPending, queueAttendance } from '../../lib/offline'
import { useOnline } from '../../lib/useOnline'
import { Badge, Button, Card, EmptyState, Select, Spinner } from '../../components/ui'
import { prettySkill } from '../../lib/constants'

type Status = 'present' | 'half_day' | 'absent'

export default function Attendance() {
  const { t } = useTranslation()
  const qc = useQueryClient()
  const online = useOnline()
  const today = new Date().toISOString().slice(0, 10)
  const [date, setDate] = useState(today)
  const [worksiteId, setWorksiteId] = useState<string>('')
  const [local, setLocal] = useState<Record<string, Status>>({})

  const pending = useLiveQuery(() => db.attendanceQueue.where('synced').equals(0).count(), [], 0)
  const { data: worksites } = useQuery({ queryKey: ['worksites'], queryFn: employer.listWorksites })
  const { data: sheet, isLoading } = useQuery({
    queryKey: ['sheet', worksiteId, date],
    queryFn: () => employer.attendanceSheet(worksiteId || null, date),
  })

  useEffect(() => {
    if (worksites && !worksiteId && worksites[0]) setWorksiteId(worksites[0].id)
  }, [worksites, worksiteId])

  // reset local toggles when sheet changes; default unmarked workers to 'present'
  useEffect(() => {
    if (!sheet) return
    const next: Record<string, Status> = {}
    for (const r of sheet) if (!r.status) next[r.worker_id] = 'present'
    setLocal(next)
  }, [sheet])

  const unmarked = (sheet ?? []).filter((r) => !r.status)

  async function submit() {
    const records = unmarked.map((r) => ({ worker_id: r.worker_id, status: local[r.worker_id] ?? 'present' }))
    if (records.length === 0) {
      toast('All workers already marked for this date')
      return
    }
    await queueAttendance(worksiteId || null, date, records)
    if (online) {
      toast.success('Attendance submitted — SMS sent to workers')
      setTimeout(() => qc.invalidateQueries({ queryKey: ['sheet'] }), 600)
    } else {
      toast('📴 Saved offline — will sync when back online', { icon: '💾' })
    }
  }

  async function manualSync() {
    const res = await flushPending()
    if (res.synced) {
      toast.success(`Synced ${res.synced} record(s)`)
      qc.invalidateQueries({ queryKey: ['sheet'] })
    } else if (!online) {
      toast('Still offline')
    } else {
      toast('Nothing to sync')
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-bold text-ink">{t('attendance')}</h1>
        <div className="flex items-center gap-2">
          <span className={online ? 'text-xs font-medium text-green-600' : 'text-xs font-medium text-amber-600'}>
            {online ? '● Online' : '○ Offline'}
          </span>
          {pending! > 0 && (
            <button onClick={manualSync} className="rounded-full bg-amber-100 px-3 py-1 text-xs font-medium text-amber-800">
              {pending} pending — sync now
            </button>
          )}
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <Select value={worksiteId} onChange={(e) => setWorksiteId(e.target.value)} className="max-w-xs">
          <option value="">All worksites</option>
          {worksites?.map((w) => <option key={w.id} value={w.id}>{w.name}</option>)}
        </Select>
        <input type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} className="rounded-lg border border-ink px-3 py-2.5" />
      </div>

      <Card className="border-dashed border-amber-300 bg-amber-50/50">
        <p className="text-sm text-amber-800">
          💡 <b>Demo the offline magic:</b> open DevTools → Network → <b>Offline</b>, mark workers, hit submit (saves
          locally), then go <b>Online</b> — it auto-syncs and SMS fire on the 📱 phone.
        </p>
      </Card>

      {isLoading ? (
        <div className="flex justify-center py-16"><Spinner /></div>
      ) : !sheet?.length ? (
        <EmptyState title="No workers at this worksite" hint="Register workers and assign them to this site." />
      ) : (
        <div className="overflow-hidden rounded-xl border border-rule bg-white">
          {sheet.map((r) => (
            <div key={r.worker_id} className="flex flex-wrap items-center justify-between gap-3 border-b border-rule px-4 py-3 last:border-0">
              <div>
                <p className="font-medium text-ink">{r.full_name}</p>
                <p className="text-xs text-ink-soft">{r.skills?.map(prettySkill).join(', ') || r.role_title || '—'}</p>
              </div>
              {r.status ? (
                <Badge color={r.status === 'absent' ? 'red' : r.status === 'half_day' ? 'amber' : 'green'}>
                  ✓ {r.status.replace('_', '-')}
                </Badge>
              ) : (
                <div className="flex gap-1">
                  {(['present', 'half_day', 'absent'] as Status[]).map((s) => (
                    <button
                      key={s}
                      onClick={() => setLocal((m) => ({ ...m, [r.worker_id]: s }))}
                      className={clsx(
                        'rounded-lg px-3 py-1.5 text-sm font-medium',
                        local[r.worker_id] === s
                          ? s === 'present' ? 'bg-green-600 text-white' : s === 'half_day' ? 'bg-amber-500 text-white' : 'bg-red-500 text-white'
                          : 'bg-slate-100 text-ink-soft',
                      )}
                    >
                      {s === 'present' ? t('present') : s === 'half_day' ? t('half') : t('absent')}
                    </button>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {unmarked.length > 0 && (
        <Button onClick={submit} className="w-full sm:w-auto">{t('submitAttendance')} ({unmarked.length})</Button>
      )}
    </div>
  )
}
