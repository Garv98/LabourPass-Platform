-- ============================================================
-- Real notification channel per worker (Phase 3).
-- 'sms' (Fast2SMS) | 'whatsapp' (Meta Cloud API) | 'both' | 'none'.
-- The actual sending happens in the notify-send Edge Function,
-- fired by a trigger on outbound sms_logs rows (see notify_triggers.sql).
-- Run this file alone in the SQL editor.
-- ============================================================

alter table workers add column if not exists notify_channel varchar(20) default 'both';

-- Allow employers to set a worker's channel at registration (optional field).
create or replace function emp_set_channel(p_token text, p_worker uuid, p_channel text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where employer_id = v_emp and worker_id = p_worker) then
    raise exception 'NOT_FOUND'; end if;
  if p_channel not in ('sms','whatsapp','both','none') then raise exception 'INVALID_CHANNEL'; end if;
  update workers set notify_channel = p_channel where id = p_worker;
end; $$;

grant execute on function public.emp_set_channel(text, uuid, text) to anon, authenticated;
