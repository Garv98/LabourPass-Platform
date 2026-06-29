import Dexie from 'dexie'
import type { Table } from 'dexie'
import { employer } from './api'

// Offline-first attendance queue. Writes land here instantly (even with no
// network); flushPending() drains to Supabase when back online. Idempotent
// per (worksite,date) on the server (first-mark-wins), so replays are safe.
export interface QueuedAttendance {
  id: string // `${worksiteId}|${date}` — natural idempotency key
  worksiteId: string | null
  date: string
  records: { worker_id: string; status: string }[]
  createdAt: number
  synced: number // 0 = pending, 1 = synced
}

class LabourPassDB extends Dexie {
  attendanceQueue!: Table<QueuedAttendance, string>
  constructor() {
    super('labourpass')
    this.version(1).stores({ attendanceQueue: 'id, synced, createdAt' })
  }
}

export const db = new LabourPassDB()

export async function queueAttendance(
  worksiteId: string | null,
  date: string,
  records: { worker_id: string; status: string }[],
) {
  const id = `${worksiteId ?? 'none'}|${date}`
  await db.attendanceQueue.put({ id, worksiteId, date, records, createdAt: Date.now(), synced: 0 })
  // try immediate flush; ignore failure (will retry on reconnect)
  void flushPending()
  return id
}

let flushing = false
export async function flushPending(): Promise<{ synced: number; failed: number }> {
  if (flushing || !navigator.onLine) return { synced: 0, failed: 0 }
  flushing = true
  let synced = 0
  let failed = 0
  try {
    const pending = await db.attendanceQueue.where('synced').equals(0).toArray()
    for (const item of pending) {
      try {
        await employer.markAttendance(item.worksiteId, item.date, item.records)
        await db.attendanceQueue.update(item.id, { synced: 1 })
        synced++
      } catch {
        failed++
      }
    }
  } finally {
    flushing = false
  }
  return { synced, failed }
}

export async function pendingCount(): Promise<number> {
  return db.attendanceQueue.where('synced').equals(0).count()
}

// Auto-flush whenever the browser regains connectivity.
if (typeof window !== 'undefined') {
  window.addEventListener('online', () => {
    void flushPending()
  })
}
