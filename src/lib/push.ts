// Web Push subscription helper. Permission must be requested from a user
// gesture (a button) — never on load. Workers who use feature phones can't
// use this; they continue on SMS. This is a complement, not a replacement.

const PUBLIC_VAPID = import.meta.env.VITE_VAPID_PUBLIC_KEY as string | undefined

export function pushSupported(): boolean {
  return (
    typeof navigator !== 'undefined' &&
    'serviceWorker' in navigator &&
    'PushManager' in window &&
    'Notification' in window &&
    Boolean(PUBLIC_VAPID)
  )
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4)
  const normalized = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(normalized)
  const out = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}

export type SaveSub = (sub: Record<string, unknown>) => Promise<unknown>
export type PushResult = 'ok' | 'denied' | 'unsupported' | 'error'

export async function enablePush(save: SaveSub): Promise<PushResult> {
  if (!pushSupported() || !PUBLIC_VAPID) return 'unsupported'
  try {
    const permission = await Notification.requestPermission()
    if (permission !== 'granted') return 'denied'
    const reg = await navigator.serviceWorker.ready
    let sub = await reg.pushManager.getSubscription()
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(PUBLIC_VAPID),
      })
    }
    await save(sub.toJSON() as Record<string, unknown>)
    return 'ok'
  } catch {
    return 'error'
  }
}
