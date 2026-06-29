import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { clsx } from 'clsx'
import toast from 'react-hot-toast'
import { auth } from '../lib/api'
import { setSession } from '../lib/session'
import { Button, Field, Input } from '../components/ui'
import { Emblem } from '../components/Emblem'
import { PhoneSim } from '../components/PhoneSim'

type Tab = 'employer' | 'admin'

export default function Landing() {
  const [params] = useSearchParams()
  const [tab, setTab] = useState<Tab>(params.get('role') === 'admin' ? 'admin' : 'employer')

  return (
    <div className="grid min-h-full lg:grid-cols-[1.05fr_1fr]">
      <Cover tab={tab} />
      <main className="flex items-center justify-center px-6 py-10 sm:px-10" style={{ background: '#fffdf6' }}>
        <div className="w-full max-w-md">
          <p className="text-sm font-semibold uppercase tracking-[0.12em] text-band">Sign in</p>
          <h2 className="mt-1 text-3xl font-bold text-ink">Sign in to your account</h2>
          <p className="text-base text-ink-soft">Manage workers, attendance, wages and records.</p>

          {/* underline tabs */}
          <div className="mt-6 flex gap-8 border-b-2 border-rule">
            <Tab label="Employer" sub="Contractor / supervisor" active={tab === 'employer'} onClick={() => setTab('employer')} />
            <Tab label="Admin" sub="NGO / Government" active={tab === 'admin'} onClick={() => setTab('admin')} />
          </div>

          <div className="mt-6">{tab === 'employer' ? <EmployerSignIn /> : <AdminSignIn />}</div>

          <WorkerLookup />
        </div>
      </main>
    </div>
  )
}

function Cover({ tab }: { tab: Tab }) {
  return (
    <aside className="relative flex flex-col justify-between overflow-hidden px-6 py-10 text-[#fdfae9] sm:px-10" style={{ background: '#0b4f4a' }}>
      {/* faint seal watermark */}
      <div className="pointer-events-none absolute -right-16 -bottom-16 text-[#99f6e4] opacity-[0.06]">
        <Emblem size={360} />
      </div>
      {/* corner stamp */}
      <div className="lp-stamp absolute right-6 top-6 hidden text-[#ffd9cf] sm:block" style={{ borderColor: '#ffd9cf' }}>
        Verified
      </div>

      <div className="relative">
        <div className="flex items-center gap-2 text-[#99f6e4]">
          <Emblem size={30} />
          <span className="text-sm font-semibold uppercase tracking-[0.14em]">India · Informal workforce</span>
        </div>
        <h1 className="mt-4 text-4xl font-bold leading-[1.05] sm:text-5xl">Work<br />Passbook</h1>
        <p className="mt-3 text-lg font-semibold text-[#cffaf0]">LabourPass — Work Identity &amp; Wage Protection</p>
        <p className="mt-4 max-w-md text-base text-[#bfeee6]">
          A tamper-proof record of attendance, wages and experience for every worker — built for a basic phone, no app needed.
        </p>
      </div>

      {/* feature phone — the product story, framed as hero, shows the live OTP */}
      <div className="relative my-8 flex items-center gap-5">
        <div className="shrink-0 overflow-hidden rounded-[1.5rem] border-4 border-[#08423d] shadow-[6px_6px_0_0_#08423d]">
          <PhoneSim compact />
        </div>
        <div className="hidden text-sm text-[#bfeee6] sm:block">
          {tab === 'employer' ? (
            <>
              <p className="font-semibold text-[#fdfae9]">Your OTP appears here</p>
              <p>Send the code, then read it on this phone — exactly how a worker receives every update.</p>
            </>
          ) : (
            <>
              <p className="font-semibold text-[#fdfae9]">Workers need no app</p>
              <p>Every attendance mark and wage payment reaches them as a plain SMS, shown here.</p>
            </>
          )}
        </div>
      </div>

      <div className="relative">
        <div className="grid grid-cols-3 border-t border-[#2e6b64] pt-4 text-center">
          <CoverStat value="450M+" en="informal workers" />
          <CoverStat value="89%" en="of India's jobs" />
          <CoverStat value="~50%" en="of GDP" />
        </div>
        <p className="mt-4 text-sm tracking-wide text-[#9fdcd3]">Tamper-evident · Verified · Free to use</p>
      </div>
    </aside>
  )
}

function CoverStat({ value, en }: { value: string; en: string }) {
  return (
    <div>
      <div className="text-xl font-bold text-[#fdfae9]">{value}</div>
      <div className="text-xs text-[#9fdcd3]">{en}</div>
    </div>
  )
}

function Tab({ label, sub, active, onClick }: { label: string; sub: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={clsx(
        '-mb-0.5 min-h-12 border-b-[3px] px-1 pb-2 text-left font-semibold',
        active ? 'border-band text-ink' : 'border-transparent text-ink-soft hover:text-ink',
      )}
    >
      <span className="block text-lg leading-tight">{label}</span>
      <span className="block text-sm opacity-80">{sub}</span>
    </button>
  )
}

function EmployerSignIn() {
  const navigate = useNavigate()
  const [phone, setPhone] = useState('9876543210')
  const [otp, setOtp] = useState('')
  const [stage, setStage] = useState<'phone' | 'otp'>('phone')
  const [busy, setBusy] = useState(false)

  async function sendOtp() {
    setBusy(true)
    try {
      await auth.otpSend(phone)
      setStage('otp')
      toast.success('OTP sent — read it on the phone')
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  async function verify() {
    setBusy(true)
    try {
      const res = await auth.otpVerify(phone, otp)
      setSession(res.token, 'employer', res.employer)
      navigate('/employer')
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-4">
      <Field label="Mobile number">
        <Input value={phone} onChange={(e) => setPhone(e.target.value.replace(/\D/g, '').slice(0, 10))} inputMode="numeric" placeholder="10-digit number" disabled={stage === 'otp'} />
      </Field>
      {stage === 'phone' ? (
        <Button onClick={sendOtp} disabled={busy || phone.length !== 10} className="w-full">Send OTP</Button>
      ) : (
        <>
          <Field label="Enter OTP">
            <Input value={otp} onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))} inputMode="numeric" placeholder="6-digit code" className="tracking-[0.4em]" />
          </Field>
          <Button onClick={verify} disabled={busy || otp.length !== 6} className="w-full">Verify &amp; sign in</Button>
          <button onClick={sendOtp} className="min-h-10 w-full text-base font-semibold text-band hover:underline">Resend OTP</button>
        </>
      )}
      <p className="text-sm text-ink-soft">Demo phone: <b className="font-mono">9876543210</b></p>
    </div>
  )
}

function AdminSignIn() {
  const navigate = useNavigate()
  const [email, setEmail] = useState('admin@labourpass.in')
  const [password, setPassword] = useState('admin123')
  const [busy, setBusy] = useState(false)

  async function login() {
    setBusy(true)
    try {
      const res = await auth.adminLogin(email, password)
      setSession(res.token, 'admin', res.admin)
      navigate('/admin')
    } catch (e) {
      toast.error((e as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-4">
      <Field label="Email"><Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" /></Field>
      <Field label="Password"><Input value={password} onChange={(e) => setPassword(e.target.value)} type="password" onKeyDown={(e) => e.key === 'Enter' && login()} /></Field>
      <Button onClick={login} disabled={busy} className="w-full">Sign in</Button>
      <p className="text-sm text-ink-soft">Demo: admin@labourpass.in / admin123</p>
    </div>
  )
}

function WorkerLookup() {
  const navigate = useNavigate()
  const [regNo, setRegNo] = useState('')
  return (
    <div className="mt-8 border-t-2 border-rule pt-5">
      <p className="text-base font-semibold text-ink">Are you a worker?</p>
      <p className="text-sm text-ink-soft">Enter your registration number to view your passbook.</p>
      <div className="mt-2 flex flex-wrap gap-2">
        <Input value={regNo} onChange={(e) => setRegNo(e.target.value.toUpperCase())} placeholder="LP-SUN001" className="max-w-44 font-mono" />
        <Button variant="outline" onClick={() => regNo && navigate(`/verify/passbook/${regNo}`)} disabled={!regNo}>View</Button>
        <Link to="/phone" className="inline-flex min-h-12 items-center gap-2 px-2 text-base font-semibold text-band hover:underline">📱 Phone demo</Link>
      </div>
    </div>
  )
}
