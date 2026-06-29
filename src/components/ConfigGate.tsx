import type { ReactNode } from 'react'
import { supabaseConfigured } from '../lib/supabase'

// Friendly setup screen if env vars are missing (so the app never white-screens).
export function ConfigGate({ children }: { children: ReactNode }) {
  if (supabaseConfigured) return <>{children}</>
  return (
    <div className="mx-auto max-w-xl px-4 py-16">
      <h1 className="text-2xl font-bold text-brand-800">🪪 LabourPass — Setup</h1>
      <p className="mt-3 text-slate-600">
        Supabase env vars are missing. Create <code className="rounded bg-slate-100 px-1">.env.local</code> from{' '}
        <code className="rounded bg-slate-100 px-1">.env.example</code> with your project URL and anon key, run the SQL
        migrations in <code className="rounded bg-slate-100 px-1">supabase/migrations</code>, then restart{' '}
        <code className="rounded bg-slate-100 px-1">npm run dev</code>.
      </p>
      <pre className="mt-4 overflow-x-auto rounded-lg bg-slate-900 p-4 text-xs text-slate-100">
{`VITE_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR-ANON-KEY`}
      </pre>
    </div>
  )
}
