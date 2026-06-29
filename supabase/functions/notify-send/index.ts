// Supabase Edge Function: notify-send
// Fired by a trigger on every OUTBOUND sms_logs row. Delivers the message to
// the worker's real phone via Fast2SMS (SMS) and/or WhatsApp Cloud API,
// based on the worker's notify_channel. Cost is capped by an allowlist: only
// numbers in SMS_LIVE_NUMBERS get a real send; everyone else stays simulated.
//
// Deploy:  supabase functions deploy notify-send --no-verify-jwt
// Secrets:
//   supabase secrets set WEBHOOK_SECRET=... \
//     SMS_LIVE_NUMBERS=9876543210,9000000001 \
//     FAST2SMS_API_KEY=... \
//     WHATSAPP_TOKEN=... WHATSAPP_PHONE_ID=...

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')
const ALLOWLIST = (Deno.env.get('SMS_LIVE_NUMBERS') ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean)

const FAST2SMS_API_KEY = Deno.env.get('FAST2SMS_API_KEY')
const WHATSAPP_TOKEN = Deno.env.get('WHATSAPP_TOKEN')
const WHATSAPP_PHONE_ID = Deno.env.get('WHATSAPP_PHONE_ID')

async function sendSms(phone: string, message: string) {
  if (!FAST2SMS_API_KEY) throw new Error('FAST2SMS_API_KEY not set')
  const res = await fetch('https://www.fast2sms.com/dev/bulkV2', {
    method: 'POST',
    headers: { authorization: FAST2SMS_API_KEY, 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ route: 'q', message, language: 'english', flash: '0', numbers: phone }),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`fast2sms ${res.status}: ${text}`)
  return 'sms'
}

async function sendWhatsApp(phone: string, message: string) {
  if (!WHATSAPP_TOKEN || !WHATSAPP_PHONE_ID) throw new Error('WhatsApp creds not set')
  const res = await fetch(`https://graph.facebook.com/v21.0/${WHATSAPP_PHONE_ID}/messages`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${WHATSAPP_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to: `91${phone}`, type: 'text', text: { body: message } }),
  })
  const text = await res.text()
  if (!res.ok) throw new Error(`whatsapp ${res.status}: ${text}`)
  return 'whatsapp'
}

Deno.serve(async (req) => {
  if (WEBHOOK_SECRET && req.headers.get('x-webhook-secret') !== WEBHOOK_SECRET) {
    return new Response('forbidden', { status: 401 })
  }

  const body = await req.json().catch(() => ({}))
  const row = body.record
  if (!row || row.direction !== 'outbound') return new Response('skip', { status: 200 })

  const phone: string = String(row.phone ?? '').replace(/\D/g, '').slice(-10)
  const message: string = row.message ?? ''

  // Cost guard: only allowlisted numbers get a real send.
  if (!ALLOWLIST.includes(phone)) {
    return new Response(JSON.stringify({ skipped: 'not allowlisted', phone }), { status: 200 })
  }

  // Worker channel preference (employer OTP etc. have no worker row → SMS).
  const { data: worker } = await supabase.from('workers').select('notify_channel').eq('phone', phone).maybeSingle()
  const channel: string = worker?.notify_channel ?? 'sms'
  if (channel === 'none') return new Response('channel none', { status: 200 })

  const used: string[] = []
  const errors: string[] = []
  const tasks: Promise<void>[] = []

  if (channel === 'sms' || channel === 'both') {
    tasks.push(sendSms(phone, message).then((c) => { used.push(c) }).catch((e) => errors.push(String(e))))
  }
  if (channel === 'whatsapp' || channel === 'both') {
    tasks.push(sendWhatsApp(phone, message).then((c) => { used.push(c) }).catch((e) => errors.push(String(e))))
  }
  await Promise.all(tasks)

  await supabase
    .from('sms_logs')
    .update({
      status: used.length ? 'sent' : 'failed',
      gateway: used.length ? used.join('+') : 'failed',
      error_message: errors.length ? errors.join(' | ') : null,
      delivered_at: used.length ? new Date().toISOString() : null,
    })
    .eq('id', row.id)

  return new Response(JSON.stringify({ used, errors }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
