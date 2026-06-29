export const SKILLS = [
  'mason', 'plumber', 'electrician', 'painter', 'carpenter', 'welder', 'helper',
  'domestic_worker', 'agricultural_labourer', 'driver', 'security_guard', 'cleaner', 'cook', 'other',
] as const

export const LANGUAGES = [
  { code: 'hi', label: 'हिंदी' },
  { code: 'en', label: 'English' },
  { code: 'kn', label: 'ಕನ್ನಡ' },
  { code: 'ta', label: 'தமிழ்' },
  { code: 'te', label: 'తెలుగు' },
  { code: 'bn', label: 'বাংলা' },
  { code: 'mr', label: 'मराठी' },
  { code: 'gu', label: 'ગુજરાતી' },
  { code: 'or', label: 'ଓଡ଼ିଆ' },
] as const

export const PAYMENT_MODES = ['cash', 'upi', 'bank_transfer', 'cheque'] as const

export function prettySkill(s: string): string {
  return s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}
