import { Navigate, useLocation } from 'react-router-dom'
import type { ReactNode } from 'react'
import { getRole, getToken } from '../lib/session'
import type { Role } from '../lib/session'

export function RequireAuth({ role, children }: { role: Role; children: ReactNode }) {
  const location = useLocation()
  const token = getToken()
  const current = getRole()
  if (!token || current !== role) {
    return <Navigate to={`/?role=${role}`} state={{ from: location }} replace />
  }
  return <>{children}</>
}
