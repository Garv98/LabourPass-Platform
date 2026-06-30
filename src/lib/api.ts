import { supabase } from './supabase'
import { clearSession, getToken } from './session'

// Maps Postgres RAISE exceptions to friendly messages.
const ERRORS: Record<string, string> = {
  INVALID_PHONE: 'Enter a valid 10-digit phone number.',
  RATE_LIMITED: 'Too many requests. Try again later.',
  OTP_EXPIRED: 'OTP expired. Request a new one.',
  OTP_INVALID: 'Incorrect OTP.',
  OTP_LOCKED: 'Too many wrong attempts. Request a new OTP.',
  INVALID_CREDENTIALS: 'Wrong email or password.',
  UNAUTHORIZED: 'Session expired. Please log in again.',
  SUSPENDED: 'This account is suspended.',
  NOT_FOUND: 'Not found.',
}

function friendly(message: string): string {
  for (const key of Object.keys(ERRORS)) {
    if (message.includes(key)) return ERRORS[key]
  }
  return message
}

export async function rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) {
    // Session expired mid-use → clear it and bounce to the sign-in hub once.
    if (error.message.includes('UNAUTHORIZED') && getToken()) {
      clearSession()
      if (typeof window !== 'undefined' && window.location.pathname !== '/') {
        window.location.assign('/?expired=1')
      }
    }
    throw new Error(friendly(error.message))
  }
  return data as T
}

// token-injecting helper for authed RPCs
function authed<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  return rpc<T>(fn, { p_token: getToken(), ...args })
}

// ---------------- AUTH ----------------
export const auth = {
  otpSend: (phone: string) => rpc('otp_send', { p_phone: phone }),
  otpVerify: (phone: string, code: string) =>
    rpc<{ token: string; employer: Employer }>('otp_verify', { p_phone: phone, p_code: code }),
  adminLogin: (email: string, password: string) =>
    rpc<{ token: string; admin: { id: string; email: string; full_name: string } }>('admin_login', {
      p_email: email,
      p_password: password,
    }),
  logout: () => authed('app_logout'),
}

// ---------------- EMPLOYER ----------------
export const employer = {
  me: () => authed<EmployerMe>('emp_me'),
  registerWorker: (payload: Record<string, unknown>) =>
    authed<{ worker: { id: string }; engagement_id: string }>('emp_register_worker', { p_payload: payload }),
  setChannel: (workerId: string, channel: string) => authed('emp_set_channel', { p_worker: workerId, p_channel: channel }),
  updateWorker: (workerId: string, payload: Record<string, unknown>) =>
    authed('emp_update_worker', { p_worker: workerId, p_payload: payload }),
  listWorkers: (search?: string) => authed<WorkerRow[]>('emp_list_workers', { p_search: search ?? null }),
  workerDetail: (workerId: string) => authed<WorkerDetail>('emp_worker_detail', { p_worker: workerId }),
  listWorksites: () => authed<Worksite[]>('emp_list_worksites'),
  createWorksite: (payload: Record<string, unknown>) => authed<Worksite>('emp_create_worksite', { p_payload: payload }),
  attendanceSheet: (worksiteId: string | null, date: string) =>
    authed<AttendanceSheetRow[]>('emp_attendance_sheet', { p_worksite: worksiteId, p_date: date }),
  markAttendance: (worksiteId: string | null, date: string, records: { worker_id: string; status: string }[]) =>
    authed<{ marked: number; sms_queued: number }>('emp_mark_attendance', {
      p_worksite: worksiteId,
      p_date: date,
      p_records: records,
    }),
  recordWage: (payload: Record<string, unknown>) => authed('emp_record_wage', { p_payload: payload }),
  sendTrustSms: (wageId: string) => authed('emp_send_trust_sms', { p_wage: wageId }),
  issueCertificate: (payload: Record<string, unknown>) => authed('emp_issue_certificate', { p_payload: payload }),
  listCertificates: () => authed<CertRow[]>('emp_list_certificates'),
  listWages: () => authed<WageRow[]>('emp_list_wages'),
  wageAnalytics: () => authed<WageAnalytics>('emp_wage_analytics'),
  trustSummary: () => authed<TrustSummary>('emp_trust_summary'),
  recentActivity: () => authed<Activity[]>('emp_recent_activity'),
  alerts: () => authed<EmpAlerts>('emp_alerts'),
  updateProfile: (payload: Record<string, unknown>) => authed<Employer>('emp_update_profile', { p_payload: payload }),
  savePush: (sub: Record<string, unknown>) => authed('emp_save_push', { p_sub: sub }),
}

// ---------------- ADMIN ----------------
export const admin = {
  dashboard: () => authed<AdminDashboard>('admin_dashboard'),
  listEmployers: (status?: string) => authed<AdminEmployer[]>('admin_list_employers', { p_status: status ?? null }),
  approveEmployer: (id: string) => authed('admin_approve_employer', { p_employer: id }),
  suspendEmployer: (id: string) => authed('admin_suspend_employer', { p_employer: id }),
  listWorkers: (search?: string) => authed<AdminWorker[]>('admin_list_workers', { p_search: search ?? null }),
  listDisputes: (status?: string) => authed<Dispute[]>('admin_list_disputes', { p_status: status ?? null }),
  updateDispute: (id: string, status: string, notes?: string) =>
    authed('admin_update_dispute', { p_dispute: id, p_status: status, p_notes: notes ?? null }),
  smsLogs: (limit = 100) => authed<SmsLog[]>('admin_sms_logs', { p_limit: limit }),
  trustScores: () => authed<TrustScoreRow[]>('admin_trust_scores'),
  wageAnalytics: () => authed<AdminWageAnalytics>('admin_wage_analytics'),
  wageIndex: () => authed<WageIndex>('admin_wage_index'),
  revokeCertificate: (id: string, reason: string) => authed('admin_revoke_certificate', { p_cert: id, p_reason: reason }),
}

// ---------------- PUBLIC ----------------
export const pub = {
  passbook: (publicId: string) => rpc<Passbook>('pub_passbook', { p_public_id: publicId }),
  verifyCertificate: (certNo: string) => rpc<CertVerify>('pub_verify_certificate', { p_cert_no: certNo }),
  verifyChain: (publicId: string) => rpc<ChainVerify>('public_verify_chain', { p_public_id: publicId }),
  ledger: (publicId: string) => rpc<Ledger>('pub_ledger', { p_public_id: publicId }),
  demoTamper: (publicId: string, restore: boolean) => rpc<{ tampered: boolean }>('demo_tamper', { p_public_id: publicId, p_restore: restore }),
  smsInbound: (sender: string, body: string) => rpc<{ reply: string }>('sms_inbound', { p_sender: sender, p_body: body }),
  savePush: (publicId: string, sub: Record<string, unknown>) => rpc('pub_save_push', { p_public_id: publicId, p_sub: sub }),
}

// ---------------- types ----------------
export interface Employer {
  id: string; phone: string; full_name: string; company_name?: string; business_type?: string; district?: string; state?: string; status: string; trust_score?: number
}
export interface EmployerMe {
  employer: Employer
  stats: { total_workers: number; active_today: number; month_wages: number; trust_score?: number }
}
export interface WorkerRow {
  id: string; public_id: string; full_name: string; phone: string; preferred_language: string
  skills?: string[]; engagement_id: string; daily_wage?: number; role_title?: string; worksite_id?: string
  days_this_month: number; last_wage_date?: string
}
export interface WorkerDetail {
  worker: Record<string, unknown> & { id: string; full_name: string; public_id: string; phone: string }
  skills: string[]
  attendance: { attendance_date: string; status: string; worksite_id?: string }[]
  wages: { id: string; payment_date: string; amount: number; payment_mode: string; days_covered?: number; employer_name: string }[]
  certificates: { certificate_no: string; role_title: string; start_date: string; end_date: string; is_revoked: boolean }[]
}
export interface Worksite { id: string; name: string; district?: string; state?: string; project_type?: string; is_active: boolean; worker_count?: number }
export interface AttendanceSheetRow { worker_id: string; full_name: string; public_id: string; role_title?: string; skills?: string[]; status: string | null }
export interface WageRow { id: string; payment_date: string; amount: number; payment_mode: string; reference_no?: string; trust_sms_sent: boolean; worker_name: string; public_id: string }
export interface WageAnalytics { by_month: { month: string; total: number; payments: number }[]; by_mode: { mode: string; total: number }[]; total_disbursed: number }
export interface TrustSummary {
  score?: number; total_ratings: number; positive: number; negative: number
  trend: { month: string; score: number }[]
  recent: { date: string; rating: number; worker: string }[]
}
export interface CertRow { certificate_no: string; role_title: string; start_date: string; end_date: string; is_revoked: boolean; issued_at: string; worker_name: string }
export interface AdminDashboard { workers: number; employers: number; wages_total: number; certificates: number; pending_employers: number; open_disputes: number; low_trust: number }
export interface AdminEmployer { id: string; full_name: string; company_name?: string; phone: string; state?: string; district?: string; status: string; trust_score?: number; total_workers: number; created_at: string }
export interface AdminWorker { id: string; public_id: string; full_name: string; phone: string; state?: string; district?: string; employers: number; total_wages: number }
export interface Dispute { id: string; dispute_type: string; status: string; description?: string; created_at: string; resolution_notes?: string; worker_name: string; public_id: string; phone: string; employer_name?: string }
export interface SmsLog { direction: string; phone: string; message: string; status: string; reference_type?: string; created_at: string }
export interface TrustScoreRow { id: string; full_name: string; company_name?: string; trust_score?: number; ratings: number }
export interface AdminWageAnalytics { by_state: { state: string; total: number; payments: number }[]; by_skill: { skill: string; workers: number }[]; by_month: { month: string; total: number }[] }
export interface Passbook {
  found: boolean
  worker?: { name: string; public_id: string; state?: string; district?: string; skills: string[] }
  summary?: { days_worked: number; days_absent: number; total_wages: number; employers: number; certificates: number }
  wages?: { payment_date: string; amount: number; mode: string; employer: string }[]
  employers?: string[]
  certificates?: { certificate_no: string; role_title: string; start_date: string; end_date: string }[]
}
export interface CertVerify {
  found: boolean; valid?: boolean
  certificate?: {
    certificate_no: string; worker_name: string; worker_public_id: string; employer_name: string; role: string
    skills: string[]; worksite: string; start_date: string; end_date: string; total_days: number
    conduct: string; issued_at: string; is_revoked: boolean; revoke_reason?: string
  }
}
export interface ChainVerify {
  found: boolean; public_id?: string
  wage?: { total: number; intact: boolean; broken_at: number | null }
  attendance?: { total: number; intact: boolean; broken_at: number | null }
}
export interface Ledger {
  found: boolean
  blocks?: { seq: number; date: string; amount: number; mode: string; employer: string; prev: string; hash: string; ok: boolean }[]
}
export interface Activity { type: string; label: string; event_at: string }
export interface EmpAlerts {
  unpaid: { id: string; full_name: string; public_id: string; last_worked: string; last_paid: string | null; recent_days: number }[]
}
export interface WageIndex {
  by_skill: { skill: string; avg_wage: number; workers: number }[]
  by_state: { state: string; avg_wage: number; workers: number }[]
  overall_avg: number
}
