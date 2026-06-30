-- ============================================================
-- Remove a worker (employer-scoped, safe).
--  • Worker shared with other employers → just deactivate THIS
--    employer's engagement (drops from your roster, keeps history).
--  • Worker exclusive to this employer → full delete of the worker
--    and all their records. Run this file alone.
-- ============================================================
create or replace function emp_remove_worker(p_token text, p_worker uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_phone text;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where employer_id = v_emp and worker_id = p_worker) then
    raise exception 'NOT_FOUND'; end if;

  -- shared with another employer → just unlink from this employer
  if exists (select 1 from engagements where worker_id = p_worker and employer_id <> v_emp) then
    update engagements set is_active = false, updated_at = now()
      where worker_id = p_worker and employer_id = v_emp;
    update employers set total_workers = (select count(distinct worker_id) from engagements where employer_id = v_emp and is_active)
      where id = v_emp;
    return jsonb_build_object('result', 'unlinked');
  end if;

  -- exclusive → full delete (FK-safe order)
  select phone into v_phone from workers where id = p_worker;
  delete from trust_ratings           where worker_id = p_worker;
  delete from wage_records            where worker_id = p_worker;
  delete from attendance_records      where worker_id = p_worker;
  delete from experience_certificates where worker_id = p_worker;
  delete from disputes                where worker_id = p_worker;
  delete from worker_skills           where worker_id = p_worker;
  delete from engagements             where worker_id = p_worker;
  delete from push_subscriptions      where actor_type = 'worker' and actor_id = p_worker;
  if v_phone is not null then delete from sms_logs where phone = v_phone; end if;
  delete from workers                 where id = p_worker;

  update employers set total_workers = (select count(distinct worker_id) from engagements where employer_id = v_emp and is_active)
    where id = v_emp;

  insert into audit_logs(actor_id, actor_type, action, table_name, record_id, new_values)
    values (v_emp, 'employer', 'worker.remove', 'workers', p_worker, jsonb_build_object('phone', v_phone));

  return jsonb_build_object('result', 'deleted');
end; $$;

grant execute on function public.emp_remove_worker(text, uuid) to anon, authenticated;
