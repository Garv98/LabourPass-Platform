import { useEffect, useRef, useState } from 'react'
import { clsx } from 'clsx'
import toast from 'react-hot-toast'
import { supabase, supabaseConfigured } from '../lib/supabase'
import { pub } from '../lib/api'

interface Msg {
  id?: string
  direction: 'outbound' | 'inbound'
  message: string
  created_at: string
}

const DEMO_PHONES = [
  { phone: '9000000001', name: 'Sunita Devi' },
  { phone: '9000000002', name: 'Raju Sharma' },
  { phone: '9876543210', name: 'Employer (OTP)' },
]

const QUICK = ['PROFILE', 'WAGES', 'PASSBOOK', '1', '2', 'HELP']

export function PhoneSim({ compact = false }: { compact?: boolean }) {
  const [phone, setPhone] = useState(DEMO_PHONES[0].phone)
  const [msgs, setMsgs] = useState<Msg[]>([])
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!supabaseConfigured) return
    let active = true
    setMsgs([])
    // history
    supabase
      .from('sms_logs')
      .select('id,direction,message,created_at')
      .eq('phone', phone)
      .order('created_at', { ascending: true })
      .limit(50)
      .then(({ data }) => {
        if (active && data) setMsgs(data as Msg[])
      })
    // realtime
    const channel = supabase
      .channel('sms-' + phone)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'sms_logs', filter: `phone=eq.${phone}` },
        (payload) => {
          setMsgs((m) => [...m, payload.new as Msg])
        },
      )
      .subscribe()
    return () => {
      active = false
      supabase.removeChannel(channel)
    }
  }, [phone])

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
  }, [msgs])

  async function send(body: string) {
    if (!body.trim()) return
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

  return (
    <div className={clsx('flex flex-col', compact ? 'h-[520px] w-[300px]' : 'h-[600px] w-[340px]')}>
      <div className="rounded-t-[2rem] bg-slate-900 px-4 pt-3 pb-2">
        <div className="mx-auto mb-2 h-1.5 w-16 rounded-full bg-slate-700" />
        <select
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          className="w-full rounded bg-slate-800 px-2 py-1 text-xs text-slate-100 outline-none"
        >
          {DEMO_PHONES.map((p) => (
            <option key={p.phone} value={p.phone}>
              📱 {p.name} · {p.phone}
            </option>
          ))}
        </select>
      </div>

      <div ref={scrollRef} className="flex-1 space-y-2 overflow-y-auto bg-slate-100 px-3 py-3">
        {msgs.length === 0 && <p className="mt-8 text-center text-xs text-slate-400">No messages yet</p>}
        {msgs.map((m, i) => (
          <div key={m.id ?? i} className={clsx('flex', m.direction === 'inbound' ? 'justify-end' : 'justify-start')}>
            <div
              className={clsx(
                'max-w-[80%] whitespace-pre-wrap rounded-2xl px-3 py-2 text-[13px] leading-snug shadow-sm',
                m.direction === 'inbound' ? 'rounded-br-sm bg-green-600 text-white' : 'rounded-bl-sm bg-white text-slate-800',
              )}
            >
              {m.message}
            </div>
          </div>
        ))}
      </div>

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
            placeholder="Type SMS reply…"
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
