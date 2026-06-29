import { useTranslation } from 'react-i18next'

export function LangToggle() {
  const { i18n } = useTranslation()
  function toggle() {
    const next = i18n.language === 'hi' ? 'en' : 'hi'
    i18n.changeLanguage(next)
    localStorage.setItem('lp_lang', next)
  }
  return (
    <button
      onClick={toggle}
      className="rounded-lg border border-slate-300 px-2.5 py-1 text-xs font-semibold text-slate-600 hover:bg-slate-50"
      aria-label="Toggle language"
    >
      {i18n.language === 'hi' ? 'EN' : 'हिं'}
    </button>
  )
}
