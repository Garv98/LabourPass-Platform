// Supabase Edge Function: send-push
// Triggered by a Database Webhook on INSERT into wage_records / attendance_records.
// Looks up the worker's push subscriptions and sends a Web Push notification.
//
// Deploy:
//   supabase functions deploy send-push --no-verify-jwt
// Secrets:
//   supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... \
//     VAPID_SUBJECT=mailto:you@example.com WEBHOOK_SECRET=some-long-random
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

webpush.setVapidDetails(
  Deno.env.get('VAPID_SUBJECT') ?? 'mailto:admin@labourpass.in',
  Deno.env.get('VAPID_PUBLIC_KEY')!,
  Deno.env.get('VAPID_PRIVATE_KEY')!,
)

const WEBHOOK_SECRET = Deno.env.get('WEBHOOK_SECRET')

Deno.serve(async (req) => {
  // Verify the call came from our DB webhook.
  if (WEBHOOK_SECRET && req.headers.get('x-webhook-secret') !== WEBHOOK_SECRET) {
    return new Response('forbidden', { status: 401 })
  }

  const body = await req.json().catch(() => ({}))
  const table: string = body.table
  const rec = body.record
  if (!rec?.worker_id) return new Response('no worker', { status: 200 })

  // Build the message.
  let title = 'LabourPass'
  let message = ''
  if (table === 'wage_records') {
    const { data: emp } = await supabase.from('employers').select('full_name').eq('id', rec.employer_id).single()
    title = 'Wage received'
    message = `Rs.${rec.amount} from ${emp?.full_name ?? 'your employer'} on ${rec.payment_date}`
  } else if (table === 'attendance_records') {
    if (rec.status === 'absent') return new Response('skip absent', { status: 200 })
    title = 'Attendance marked'
    message = `Marked ${rec.status} on ${rec.attendance_date}`
  } else {
    return new Response('unhandled table', { status: 200 })
  }

  const { data: subs } = await supabase
    .from('push_subscriptions')
    .select('id, subscription')
    .eq('actor_type', 'worker')
    .eq('actor_id', rec.worker_id)

  const payload = JSON.stringify({ title, body: message, url: '/' })

  await Promise.all(
    (subs ?? []).map(async (s) => {
      try {
        await webpush.sendNotification(s.subscription, payload)
      } catch (err) {
        const code = (err as { statusCode?: number }).statusCode
        if (code === 404 || code === 410) {
          // subscription expired — clean it up
          await supabase.from('push_subscriptions').delete().eq('id', s.id)
        }
      }
    }),
  )

  return new Response(JSON.stringify({ sent: subs?.length ?? 0 }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  })
})
