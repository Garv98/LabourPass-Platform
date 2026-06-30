-- ============================================================
-- Edit worker profile (employer-scoped). Updates the worker's
-- details, skills (set-semantics), language/channel, and this
-- employer's engagement wage/role. Run this file alone.
-- ============================================================
create or replace function emp_update_worker(p_token text, p_worker uuid, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_skill text;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where employer_id = v_emp and worker_id = p_worker) then
    raise exception 'NOT_FOUND'; end if;

  update workers set
    full_name      = coalesce(nullif(p_payload->>'full_name',''), full_name),
    father_name    = coalesce(nullif(p_payload->>'father_name',''), father_name),
    gender         = coalesce(nullif(p_payload->>'gender',''), gender),
    aadhaar_last4  = coalesce(nullif(p_payload->>'aadhaar_last4',''), aadhaar_last4),
    state          = coalesce(nullif(p_payload->>'state',''), state),
    district       = coalesce(nullif(p_payload->>'district',''), district),
    notify_channel = coalesce(nullif(p_payload->>'notify_channel',''), notify_channel),
    preferred_language = case when p_payload ? 'preferred_language'
                              then nullif(p_payload->>'preferred_language','')::language_code
                              else preferred_language end,
    updated_at     = now()
  where id = p_worker;

  -- skills: make the set match the form (add new, drop removed)
  if p_payload ? 'skills' then
    delete from worker_skills
      where worker_id = p_worker
        and skill::text not in (select jsonb_array_elements_text(p_payload->'skills'));
    for v_skill in select jsonb_array_elements_text(p_payload->'skills') loop
      begin
        insert into worker_skills(worker_id, skill, added_by) values (p_worker, v_skill::worker_skill, v_emp)
        on conflict (worker_id, skill) do nothing;
      exception when invalid_text_representation then null;
      end;
    end loop;
  end if;

  -- this employer's engagement: wage + role
  update engagements set
    daily_wage = coalesce(nullif(p_payload->>'daily_wage','')::numeric, daily_wage),
    role_title = coalesce(nullif(p_payload->>'role_title',''), role_title),
    updated_at = now()
  where id = nullif(p_payload->>'engagement_id','')::uuid and employer_id = v_emp;

  insert into audit_logs(actor_id, actor_type, action, table_name, record_id, new_values)
    values (v_emp, 'employer', 'worker.update', 'workers', p_worker, jsonb_build_object('by', v_emp));

  return (select to_jsonb(w) from workers w where id = p_worker);
end; $$;

grant execute on function public.emp_update_worker(text, uuid, jsonb) to anon, authenticated;
