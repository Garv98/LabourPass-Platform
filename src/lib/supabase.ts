import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const supabaseConfigured = Boolean(url && anonKey)

// We roll our own session tokens (SECURITY DEFINER RPCs), so disable
// supabase-js auth persistence/refresh — we only use it for RPC + Realtime.
export const supabase = createClient(url ?? 'http://localhost', anonKey ?? 'public-anon-key', {
  auth: { persistSession: false, autoRefreshToken: false },
})

// Used only for shareable/printable links (QR, PDF, copy-to-share). In-app
// navigation uses relative paths so it never depends on this value.
export const PUBLIC_BASE_URL = (
  (import.meta.env.VITE_PUBLIC_BASE_URL as string | undefined) ?? window.location.origin
).replace(/\/+$/, '')
