import { useEffect, useMemo, useRef, useState } from 'react'
import { clsx } from 'clsx'
import toast from 'react-hot-toast'
import { supabase, supabaseConfigured } from '../lib/supabase'
import { pub } from '../lib/api'

interface Msg {
  id?: string
  direction: 'outbound' | 'inbound'
  message: string
  created_at: string
  reference_type?: string | null
}
interface Contact {
  phone: string
  name: string
}

const DEFAULT_CONTACTS: Contact[] = [
  { phone: '9000000001', name: 'Sunita Devi' },
  { phone: '9000000002', name: 'Raju Sharma' },
  { phone: '9876543210', name: 'Employer (OTP)' },
]
const STORE_KEY = 'lp_demo_contacts'

function loadContacts(): Contact[] {
  try {
    const raw = localStorage.getItem(STORE_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as Contact[]
      if (Array.isArray(parsed) && parsed.length) return parsed
    }
  } catch {
    /* ignore */
  }
  return DEFAULT_CONTACTS
}

const QUICK = ['PROFILE', 'WAGES', 'PASSBOOK', '1', '2', 'HELP']

export function PhoneSim({ compact = false }: { compact?: boolean }) {
  const [contacts, setContacts] = useState<Contact[]>(loadContacts)
  const [phone, setPhone] = useState(() => loadContacts()[0]?.phone ?? '')
  const [msgs, setMsgs] = useState<Msg[]>([])
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [manage, setManage] = useState(false)
  const [newPhone, setNewPhone] = useState('')
  const [newName, setNewName] = useState('')
  const [now, setNow] = useState(() => new Date())
  const scrollRef = useRef<HTMLDivElement>(null)

  const active = contacts.find((c) => c.phone === phone)

  function persist(next: Contact[]) {
    setContacts(next)
    localStorage.setItem(STORE_KEY, JSON.stringify(next))
  }

  function addContact() {
    const p = newPhone.replace(/\D/g, '').slice(0, 10)
    if (p.length !== 10) {
      toast.error('Enter a 10-digit number')
      return
    }
    if (!contacts.some((c) => c.phone === p)) {
      persist([...contacts, { phone: p, name: newName.trim() || `+91 ${p}` }])
    }
    setPhone(p)
    setNewPhone('')
    setNewName('')
    setManage(false)
  }

  function removeContact(p: string) {
    const next = contacts.filter((c) => c.phone !== p)
    persist(next.length ? next : DEFAULT_CONTACTS)
    if (phone === p) setPhone((next[0] ?? DEFAULT_CONTACTS[0]).phone)
  }

  // live clock for the status bar
  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 30_000)
    return () => clearInterval(t)
  }, [])

  // load history + subscribe for the active number
  useEffect(() => {
    if (!supabaseConfigured || !phone) return
    let live = true
    setMsgs([])
    supabase
      .from('sms_logs')
      .select('id,direction,message,created_at,reference_type')
      .eq('phone', phone)
      .order('created_at', { ascending: true })
      .limit(50)
      .then(({ data }) => {
        if (live && data) setMsgs(data as Msg[])
      })
    const channel = supabase
      .channel('sms-' + phone)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'sms_logs', filter: `phone=eq.${phone}` },
        (payload) => setMsgs((m) => [...m, payload.new as Msg]),
      )
      .subscribe()
    return () => {
      live = false
      supabase.removeChannel(channel)
    }
  }, [phone])

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [msgs])

  // Copy-OTP only when the most recent message is an OTP (so it doesn't linger).
  const lastOtp = useMemo(() => {
    const last = msgs[msgs.length - 1]
    if (last && last.direction === 'outbound' && last.reference_type === 'otp') {
      const m = last.message.match(/\b(\d{6})\b/)
      if (m) return m[1]
    }
    return null
  }, [msgs])

  async function send(body: string) {
    if (!body.trim() || !phone) return
    setSending(true)
    try {
      await pub.smsInbound(phone, body.trim())
      setText('')
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setSending(false)
    }
  }

  const fmtTime = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })

  return (
    <div className={clsx('flex flex-col bg-slate-100', compact ? 'h-[540px] w-[300px]' : 'h-[620px] w-[340px]')}>
      {/* status bar */}
      <div className="flex items-center justify-between bg-slate-900 px-4 pt-2 pb-1 text-[11px] font-medium text-slate-300">
        <span>{now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
        <span className="flex items-center gap-1">▮▮▮ · 4G · 🔋</span>
      </div>

      {/* contact bar */}
      <div className="flex items-center gap-2 bg-slate-800 px-3 py-2 text-white">
        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-600 text-sm font-bold">
          {(active?.name ?? '?').charAt(0).toUpperCase()}
        </div>
        <div className="min-w-0 flex-1">
          <select
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            className="w-full truncate bg-transparent text-sm font-semibold text-white outline-none"
          >
            {contacts.map((c) => (
              <option key={c.phone} value={c.phone} className="text-slate-900">
                {c.name}
              </option>
            ))}
          </select>
          <div className="text-[11px] text-slate-400">+91 {phone || '—'}</div>
        </div>
        <button
          onClick={() => setManage((m) => !m)}
          className="rounded px-2 py-1 text-xs font-semibold text-slate-300 hover:bg-slate-700"
          aria-label="Manage demo numbers"
        >
          {manage ? '✕' : '＋'}
        </button>
      </div>

      {/* manage numbers panel */}
      {manage && (
        <div className="space-y-2 border-b border-slate-300 bg-white px-3 py-2">
          <p className="text-xs font-semibold text-slate-500">Demo numbers</p>
          <div className="flex flex-wrap gap-1">
            {contacts.map((c) => (
              <span key={c.phone} className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2 py-0.5 text-xs text-slate-700">
                {c.name}
                <button onClick={() => removeContact(c.phone)} className="text-slate-400 hover:text-red-600" aria-label={`Remove ${c.name}`}>✕</button>
              </span>
            ))}
          </div>
          <div className="flex gap-1">
            <input
              value={newPhone}
              onChange={(e) => setNewPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
              placeholder="10-digit number"
              inputMode="numeric"
              className="w-32 rounded border border-slate-300 px-2 py-1 text-sm outline-none"
            />
            <input
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="Name (optional)"
              className="min-w-0 flex-1 rounded border border-slate-300 px-2 py-1 text-sm outline-none"
            />
            <button onClick={addContact} className="rounded bg-brand-700 px-3 text-sm font-semibold text-white">Add</button>
          </div>
          <p className="text-[11px] text-slate-400">Tip: add a worker's number to watch their SMS thread and reply as them.</p>
        </div>
      )}

      {/* messages */}
      <div ref={scrollRef} className="flex-1 space-y-2 overflow-y-auto px-3 py-3">
        {msgs.length === 0 && <p className="mt-8 text-center text-xs text-slate-400">No messages for this number yet</p>}
        {msgs.map((m, i) => (
          <div key={m.id ?? i} className={clsx('flex flex-col', m.direction === 'inbound' ? 'items-end' : 'items-start')}>
            <div
              className={clsx(
                'max-w-[82%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-[13px] leading-snug shadow-sm',
                m.direction === 'inbound' ? 'rounded-br-sm bg-green-600 text-white' : 'rounded-bl-sm bg-white text-slate-800',
              )}
            >
              {m.message}
            </div>
            <span className="mt-0.5 px-1 text-[10px] text-slate-400">{fmtTime(m.created_at)}</span>
          </div>
        ))}
      </div>

      {/* copy OTP helper */}
      {lastOtp && (
        <button
          onClick={() => {
            navigator.clipboard.writeText(lastOtp)
            toast.success(`OTP ${lastOtp} copied`)
          }}
          className="mx-3 mb-1 rounded-lg bg-brand-100 py-1.5 text-sm font-semibold text-brand-800"
        >
          📋 Copy OTP {lastOtp}
        </button>
      )}

      {/* composer */}
      <div className="bg-slate-200 px-2 py-2">
        <div className="mb-2 flex flex-wrap gap-1">
          {QUICK.map((q) => (
            <button
              key={q}
              onClick={() => send(q)}
              disabled={sending}
              className="rounded bg-slate-800 px-2 py-1 text-[11px] font-medium text-white hover:bg-slate-700 disabled:opacity-50"
            >
              {q}
            </button>
          ))}
        </div>
        <div className="flex gap-1">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && send(text)}
            placeholder="Reply as this worker…"
            className="flex-1 rounded-lg border border-slate-300 px-2 py-2 text-sm outline-none"
          />
          <button onClick={() => send(text)} disabled={sending} className="rounded-lg bg-brand-700 px-3 text-sm font-semibold text-white disabled:opacity-50">
            Send
          </button>
        </div>
      </div>
    </div>
  )
}

export function FloatingPhone() {
  const [open, setOpen] = useState(false)
  return (
    <div className="fixed bottom-4 right-4 z-50">
      {open && (
        <div className="mb-3 overflow-hidden rounded-[2rem] border-4 border-slate-900 shadow-2xl">
          <PhoneSim compact />
        </div>
      )}
      <button
        onClick={() => setOpen((o) => !o)}
        className="ml-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-900 text-2xl text-white shadow-lg"
        aria-label="Toggle worker phone simulator"
      >
        {open ? '✕' : '📱'}
      </button>
    </div>
  )
}
