// Lightweight client session: we roll our own opaque tokens (validated
// server-side by SECURITY DEFINER RPCs), so just persist token + role.
export type Role = 'employer' | 'admin'

const TOKEN_KEY = 'lp_token'
const ROLE_KEY = 'lp_role'
const ACTOR_KEY = 'lp_actor'

type Listener = () => void
const listeners = new Set<Listener>()

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}
export function getRole(): Role | null {
  return localStorage.getItem(ROLE_KEY) as Role | null
}
export function getActor<T = unknown>(): T | null {
  const raw = localStorage.getItem(ACTOR_KEY)
  return raw ? (JSON.parse(raw) as T) : null
}

export function setSession(token: string, role: Role, actor: unknown) {
  localStorage.setItem(TOKEN_KEY, token)
  localStorage.setItem(ROLE_KEY, role)
  localStorage.setItem(ACTOR_KEY, JSON.stringify(actor))
  listeners.forEach((l) => l())
}

export function clearSession() {
  localStorage.removeItem(TOKEN_KEY)
  localStorage.removeItem(ROLE_KEY)
  localStorage.removeItem(ACTOR_KEY)
  listeners.forEach((l) => l())
}

export function onSessionChange(l: Listener): () => void {
  listeners.add(l)
  return () => listeners.delete(l)
}
