import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { clsx } from 'clsx'
import { auth } from '../lib/api'
import { clearSession } from '../lib/session'
import { Emblem } from './Emblem'

const NAV = [
  { to: '/admin', label: 'Overview', end: true },
  { to: '/admin/employers', label: 'Employers' },
  { to: '/admin/workers', label: 'Workers' },
  { to: '/admin/disputes', label: 'Disputes' },
  { to: '/admin/trust', label: 'Trust Scores' },
  { to: '/admin/sms', label: 'SMS Logs' },
  { to: '/admin/analytics', label: 'Analytics' },
]

export function AdminLayout() {
  const navigate = useNavigate()
  async function logout() {
    try {
      await auth.logout()
    } catch {
      /* ignore */
    }
    clearSession()
    navigate('/')
  }
  return (
    <div className="min-h-full bg-paper">
      <header className="sticky top-0 z-40 border-b-2 border-ink" style={{ background: 'var(--color-ink)' }}>
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2 text-[#fdfae9]">
            <Emblem size={26} />
            <span className="font-bold">LabourPass · Administration</span>
          </div>
          <button onClick={logout} className="min-h-10 text-base font-semibold text-[#d8e6e1] hover:text-white">
            Logout
          </button>
        </div>
        <nav className="mx-auto flex max-w-6xl gap-1 overflow-x-auto px-3 pb-2">
          {NAV.map((n) => (
            <NavLink
              key={n.to}
              to={n.to}
              end={n.end}
              className={({ isActive }) =>
                clsx(
                  'min-h-10 whitespace-nowrap px-3 py-1.5 text-base font-semibold',
                  isActive ? 'bg-[#fdfae9] text-ink' : 'text-[#d8e6e1] hover:bg-band-deep',
                )
              }
            >
              {n.label}
            </NavLink>
          ))}
        </nav>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">
        <Outlet />
      </main>
    </div>
  )
}
