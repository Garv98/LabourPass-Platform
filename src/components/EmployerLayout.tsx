import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useTranslation } from 'react-i18next'
import { clsx } from 'clsx'
import { auth } from '../lib/api'
import { clearSession } from '../lib/session'
import { FloatingPhone } from './PhoneSim'
import { LangToggle } from './LangToggle'
import { Emblem } from './Emblem'

const NAV = [
  { to: '/employer', label: 'dashboard', hi: 'घर', end: true },
  { to: '/employer/workers', label: 'workers', hi: 'मज़दूर' },
  { to: '/employer/worksites', label: 'worksites', hi: 'साइट' },
  { to: '/employer/attendance', label: 'attendance', hi: 'हाज़िरी' },
  { to: '/employer/wages', label: 'wages', hi: 'वेतन' },
  { to: '/employer/certificates', label: 'certificates', hi: 'प्रमाणपत्र' },
  { to: '/employer/trust', label: 'trust', hi: 'भरोसा' },
]

export function EmployerLayout() {
  const { t } = useTranslation()
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
    <div className="min-h-full">
      <header className="sticky top-0 z-40 lp-band">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="text-brand-100"><Emblem size={26} /></span>
            <span className="font-bold text-[#fdfae9]">श्रमिक पास · LabourPass</span>
          </div>
          <div className="flex items-center gap-3">
            <LangToggle />
            <button onClick={logout} className="min-h-10 text-base font-semibold text-brand-100 hover:text-white">
              {t('logout')}
            </button>
          </div>
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
                  isActive ? 'bg-[#fdfae9] text-band-deep' : 'text-brand-100 hover:bg-band',
                )
              }
            >
              <span className="mr-1">{n.hi}</span>
              <span className="opacity-80">· {t(n.label)}</span>
            </NavLink>
          ))}
        </nav>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">
        <Outlet />
      </main>
      <FloatingPhone />
    </div>
  )
}
