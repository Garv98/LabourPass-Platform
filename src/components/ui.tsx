import { clsx } from 'clsx'
import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode, SelectHTMLAttributes } from 'react'

// Government work-passbook UI primitives. See src/index.css for tokens + lp-* classes.

export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={clsx('lp-sheet p-5', className)}>{children}</div>
}

export function Button({
  variant = 'primary',
  className,
  children,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: 'primary' | 'ghost' | 'danger' | 'outline' }) {
  return (
    <button
      className={clsx(
        'inline-flex min-h-12 items-center justify-center gap-2 border-2 px-4 text-base font-semibold transition disabled:opacity-50',
        variant === 'primary' && 'border-band-deep bg-band text-[#fdfae9] hover:bg-band-deep',
        variant === 'outline' && 'border-ink bg-white text-ink hover:bg-paper',
        variant === 'ghost' && 'border-transparent text-band hover:bg-paper',
        variant === 'danger' && 'border-stamp bg-stamp text-[#fdfae9] hover:opacity-90',
        className,
      )}
      {...props}
    >
      {children}
    </button>
  )
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1 block text-base font-semibold text-ink">{label}</span>
      {children}
    </label>
  )
}

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={clsx(
        'min-h-12 w-full border-2 border-ink bg-white px-3 text-base text-ink outline-none placeholder:text-ink-soft/60 focus:border-band',
        props.className,
      )}
    />
  )
}

export function Select(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={clsx(
        'min-h-12 w-full border-2 border-ink bg-white px-3 text-base text-ink outline-none focus:border-band',
        props.className,
      )}
    />
  )
}

export function StatCard({ label, value, accent }: { label: string; value: ReactNode; accent?: string }) {
  return (
    <div className="lp-sheet flex flex-col p-4">
      <span className="text-base font-semibold text-ink-soft">{label}</span>
      <span className={clsx('mt-1 text-3xl font-bold tabular-nums', accent ?? 'text-ink')}>{value}</span>
    </div>
  )
}

export function Badge({ children, color = 'slate' }: { children: ReactNode; color?: 'slate' | 'green' | 'red' | 'amber' | 'brand' }) {
  return (
    <span
      className={clsx(
        'inline-flex items-center border px-2.5 py-0.5 text-sm font-semibold',
        color === 'slate' && 'border-rule bg-paper text-ink-soft',
        color === 'green' && 'border-paid bg-[#eaf4ec] text-paid',
        color === 'red' && 'border-stamp bg-stamp-soft text-stamp',
        color === 'amber' && 'border-amber-ink bg-[#f7eed7] text-amber-ink',
        color === 'brand' && 'border-band bg-brand-50 text-band-deep',
      )}
    >
      {children}
    </span>
  )
}

export function Spinner() {
  return <div className="h-6 w-6 animate-spin rounded-full border-2 border-band border-t-transparent" />
}

export function EmptyState({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="flex flex-col items-center justify-center border-2 border-dashed border-rule py-12 text-center">
      <p className="text-lg font-semibold text-ink">{title}</p>
      {hint && <p className="mt-1 text-base text-ink-soft">{hint}</p>}
    </div>
  )
}

export function rupee(n: number | string | undefined): string {
  const v = Number(n ?? 0)
  return '₹' + v.toLocaleString('en-IN')
}
