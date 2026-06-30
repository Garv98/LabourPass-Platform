// Supabase Edge Function: notify-send
// Fired by a trigger on every OUTBOUND sms_logs row. Delivers the message to
// the worker's real phone via WhatsApp Cloud API when the worker's channel is
// 'whatsapp' or 'both'. ('sms'/'none' = simulated only — shown on the in-app
// demo phone, no real SMS provider.) Cost is capped by an allowlist.
//
// Deploy:  supabase functions deploy notify-send --no-verify-jwt
// Secrets:
//   supabase secrets set WEBHOOK_SECRET=... \
//     SMS_LIVE_NUMBERS=9876543210,9000000001 \
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

const WHATSAPP_TOKEN = Deno.env.get('WHATSAPP_TOKEN')
const WHATSAPP_PHONE_ID = Deno.env.get('WHATSAPP_PHONE_ID')

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

  const { data: worker } = await supabase.from('workers').select('notify_channel').eq('phone', phone).maybeSingle()
  const channel: string = worker?.notify_channel ?? 'whatsapp'

  // Only WhatsApp is a real channel now. 'sms'/'none' stay simulated (demo phone only).
  if (channel !== 'whatsapp' && channel !== 'both') {
    return new Response(JSON.stringify({ simulated: true, channel }), { status: 200 })
  }

  const used: string[] = []
  const errors: string[] = []
  try {
    used.push(await sendWhatsApp(phone, message))
  } catch (e) {
    errors.push(String(e))
  }

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
