// Supabase Edge Function: meta-inbound
// Receives inbound WhatsApp messages from the Meta Cloud API webhook and runs
// the same sms_inbound() parser the simulated phone uses. The reply is logged
// as an outbound row, which the notify-send trigger delivers back over WhatsApp
// — so a worker can text PROFILE / WAGES / PASSBOOK / DISPUTE / WAGEDISPUTE /
// 1 / 2 / HELP on a real phone and get a real reply.
//
// Deploy:  supabase functions deploy meta-inbound --no-verify-jwt
// Secret:  supabase secrets set WHATSAPP_VERIFY_TOKEN=<any-random-string>
// (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from 'npm:@supabase/supabase-js@2'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)
const VERIFY_TOKEN = Deno.env.get('WHATSAPP_VERIFY_TOKEN') ?? 'labourpass'

Deno.serve(async (req) => {
  const url = new URL(req.url)

  // 1) Webhook verification handshake (Meta sends a GET once when you save the URL).
  if (req.method === 'GET') {
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')
    if (mode === 'subscribe' && token === VERIFY_TOKEN) {
      return new Response(challenge ?? '', { status: 200 })
    }
    return new Response('forbidden', { status: 403 })
  }

  // 2) Incoming messages.
  if (req.method === 'POST') {
    try {
      const body = await req.json()
      const value = body?.entry?.[0]?.changes?.[0]?.value
      const msg = value?.messages?.[0]
      if (msg && msg.type === 'text') {
        const from = String(msg.from ?? '').replace(/\D/g, '') // e.g. 916901085253
        const phone = from.slice(-10) // our workers store 10 digits
        const text = msg.text?.body ?? ''
        // Same parser as the sim phone. The reply is logged outbound and the
        // notify-send trigger sends it back over WhatsApp.
        await supabase.rpc('sms_inbound', { p_sender: phone, p_body: text })
      }
    } catch {
      // swallow — always 200 so Meta doesn't retry-storm
    }
    return new Response('ok', { status: 200 })
  }

  return new Response('method not allowed', { status: 405 })
})
