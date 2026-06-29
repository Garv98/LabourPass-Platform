import { useState } from 'react'
import toast from 'react-hot-toast'
import { enablePush, pushSupported } from '../lib/push'
import type { SaveSub } from '../lib/push'

// Button-triggered push opt-in (browsers require a user gesture). Renders
// nothing on devices/browsers that don't support Web Push.
export function PushButton({ save, label = 'Enable updates', className }: { save: SaveSub; label?: string; className?: string }) {
  const [busy, setBusy] = useState(false)
  const [on, setOn] = useState(typeof Notification !== 'undefined' && Notification.permission === 'granted')

  if (!pushSupported()) return null

  async function go() {
    setBusy(true)
    const result = await enablePush(save)
    setBusy(false)
    if (result === 'ok') {
      setOn(true)
      toast.success('Notifications turned on')
    } else if (result === 'denied') {
      toast.error('Notifications are blocked. Allow them in your browser settings.')
    } else if (result === 'unsupported') {
      toast.error('This device cannot receive notifications.')
    } else {
      toast.error('Could not turn on notifications. Try again.')
    }
  }

  return (
    <button
      onClick={go}
      disabled={busy || on}
      className={className ?? 'min-h-10 border-2 border-ink bg-white px-3 text-sm font-semibold text-ink hover:bg-paper disabled:opacity-60'}
    >
      {on ? '🔔 Updates on' : busy ? 'Turning on…' : `🔔 ${label}`}
    </button>
  )
}
