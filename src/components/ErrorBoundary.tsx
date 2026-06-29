import { Component } from 'react'
import type { ReactNode } from 'react'

interface State { error: Error | null }

export class ErrorBoundary extends Component<{ children: ReactNode }, State> {
  state: State = { error: null }
  static getDerivedStateFromError(error: Error): State {
    return { error }
  }
  componentDidCatch(error: Error) {
    // eslint-disable-next-line no-console
    console.error('App error:', error)
  }
  render() {
    if (this.state.error) {
      return (
        <div className="mx-auto max-w-lg px-4 py-20 text-center">
          <div className="text-4xl">😕</div>
          <h1 className="mt-3 text-xl font-bold text-slate-800">Something went wrong</h1>
          <p className="mt-2 text-sm text-slate-500">{this.state.error.message}</p>
          <button onClick={() => location.assign('/')} className="mt-5 rounded-lg bg-brand-700 px-4 py-2 text-sm font-semibold text-white">
            Back to home
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
