-- ============================================================
-- RLS: lock every table to direct access. All app data flows
-- through SECURITY DEFINER RPCs (which bypass RLS). The only
-- direct-read allowance is sms_logs SELECT, needed for Realtime
-- powering the /phone simulator (messages are simulated, non-PII).
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array[
    'admin_users','employers','workers','worker_skills','worksites','engagements',
    'attendance_records','wage_records','experience_certificates','trust_ratings',
    'disputes','sms_logs','otp_requests','notifications','audit_logs','sessions'
  ] loop
    execute format('alter table %I enable row level security;', t);
  end loop;
end $$;

-- Realtime needs a SELECT policy + publication membership.
drop policy if exists sms_logs_read on sms_logs;
create policy sms_logs_read on sms_logs for select to anon, authenticated using (true);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'sms_logs'
  ) then
    alter publication supabase_realtime add table sms_logs;
  end if;
exception when undefined_object then
  -- publication doesn't exist (non-Supabase Postgres) — safe to ignore
  null;
end $$;

-- ---- Execute grants: RPCs are callable by the anon/authenticated
-- ---- roles; access control happens inside via session-token checks. ----
do $$
declare fn text;
begin
  for fn in
    select format('%I(%s)', p.proname, pg_get_function_identity_arguments(p.oid))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'otp_send','otp_verify','admin_login','app_logout',
        'emp_me','emp_register_worker','emp_list_workers','emp_worker_detail',
        'emp_create_worksite','emp_list_worksites','emp_attendance_sheet','emp_mark_attendance',
        'emp_record_wage','emp_send_trust_sms','emp_issue_certificate','emp_list_certificates',
        'emp_list_wages','emp_wage_analytics','emp_trust_summary',
        'sms_inbound','pub_passbook','pub_verify_certificate','public_verify_chain',
        'admin_dashboard','admin_list_employers','admin_approve_employer','admin_suspend_employer',
        'admin_list_workers','admin_list_disputes','admin_update_dispute','admin_sms_logs',
        'admin_trust_scores','admin_wage_analytics','admin_revoke_certificate')
  loop
    execute format('grant execute on function public.%s to anon, authenticated;', fn);
  end loop;
end $$;

-- Internal helpers must NOT be exposed.
revoke all on function public._employer_id(text) from anon, authenticated;
revoke all on function public._admin_id(text) from anon, authenticated;
revoke all on function public._send_sms(text, text, language_code, text, uuid) from anon, authenticated;
revoke all on function public.recompute_trust(uuid) from anon, authenticated;
