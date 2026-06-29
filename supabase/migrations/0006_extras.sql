-- ============================================================
-- EXTRAS: stage-safe tamper demo, visible hash-chain ledger,
-- live dashboard feed + wage-risk alerts, informal wage index.
-- Re-run this file alone in the SQL editor (all create-or-replace).
-- ============================================================

-- ---- Stage-safe tamper/restore (DEMO ONLY): mutates a wage amount
-- ---- WITHOUT recomputing record_hash, so the chain breaks. Original
-- ---- value is stashed in notes so restore is exact. No SQL on stage.
create or replace function demo_tamper(p_public_id text, p_restore boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_worker uuid; v_target uuid; v_amount numeric; v_notes text;
begin
  select id into v_worker from workers where public_id = p_public_id;
  if v_worker is null then return jsonb_build_object('found', false); end if;

  -- target the 2nd wage record in the chain (so the break is mid-chain & obvious)
  select id, amount, notes into v_target, v_amount, v_notes
    from wage_records where worker_id = v_worker order by chain_seq asc offset 1 limit 1;
  if v_target is null then
    select id, amount, notes into v_target, v_amount, v_notes
      from wage_records where worker_id = v_worker order by chain_seq asc limit 1;
  end if;
  if v_target is null then return jsonb_build_object('found', false, 'note', 'no wage records'); end if;

  if p_restore then
    if v_notes like 'DEMO_ORIG:%' then
      update wage_records set amount = split_part(v_notes, ':', 2)::numeric, notes = null where id = v_target;
    end if;
    return jsonb_build_object('found', true, 'tampered', false);
  else
    if v_notes is null or v_notes not like 'DEMO_ORIG:%' then
      update wage_records set notes = 'DEMO_ORIG:' || v_amount, amount = 1 where id = v_target;
    end if;
    return jsonb_build_object('found', true, 'tampered', true);
  end if;
end; $$;

-- ---- Visible hash-chain ledger (public, PII-safe): each wage record as a
-- ---- "block" with its hash + prev link + an integrity flag.
create or replace function pub_ledger(p_public_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_worker uuid; rec record; v_prev text := '0'; v_calc text; v_canonical text;
        v_arr jsonb := '[]'::jsonb; v_seq int := 0;
begin
  select id into v_worker from workers where public_id = p_public_id;
  if v_worker is null then return jsonb_build_object('found', false); end if;
  for rec in select * from wage_records where worker_id = v_worker order by chain_seq asc loop
    v_seq := v_seq + 1;
    v_canonical := concat_ws('|', rec.worker_id::text, rec.employer_id::text,
                             rec.payment_date::text, rec.amount::text, rec.payment_mode::text);
    v_calc := encode(extensions.digest(v_canonical || '|' || v_prev, 'sha256'), 'hex');
    v_arr := v_arr || jsonb_build_object(
      'seq', v_seq,
      'date', rec.payment_date,
      'amount', rec.amount,
      'mode', rec.payment_mode::text,
      'employer', (select full_name from employers where id = rec.employer_id),
      'prev', left(coalesce(rec.prev_hash,'0'), 12),
      'hash', left(coalesce(rec.record_hash,''), 12),
      'ok', (rec.prev_hash = v_prev and rec.record_hash = v_calc));
    v_prev := rec.record_hash;
  end loop;
  return jsonb_build_object('found', true, 'blocks', v_arr);
end; $$;

-- ---- Employer recent activity feed ----
create or replace function emp_recent_activity(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.event_at desc) from (
    (select 'wage' as type,
            'Paid Rs.' || amount || ' to ' || (select full_name from workers w where w.id = wage_records.worker_id) as label,
            created_at as event_at
       from wage_records where employer_id = v_emp order by created_at desc limit 5)
    union all
    (select 'attendance' as type,
            'Marked ' || status::text || ' - ' || (select full_name from workers w where w.id = attendance_records.worker_id) as label,
            created_at as event_at
       from attendance_records where employer_id = v_emp order by created_at desc limit 5)
    union all
    (select 'certificate' as type,
            'Certificate ' || certificate_no || ' issued' as label, issued_at as event_at
       from experience_certificates where employer_id = v_emp order by issued_at desc limit 3)
    order by event_at desc limit 10) t), '[]'::jsonb);
end; $$;

-- ---- Wage-theft / unpaid-worker risk: worked recently but no wage in 15+ days ----
create or replace function emp_alerts(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return jsonb_build_object(
    'unpaid', coalesce((select jsonb_agg(row_to_json(t)) from (
      select w.id, w.full_name, w.public_id,
             max(a.attendance_date) as last_worked,
             (select max(payment_date) from wage_records g where g.worker_id = w.id and g.employer_id = v_emp) as last_paid,
             count(*) filter (where a.status in ('present','half_day') and a.attendance_date > current_date - 30) as recent_days
      from engagements e
      join workers w on w.id = e.worker_id
      join attendance_records a on a.engagement_id = e.id
      where e.employer_id = v_emp and e.is_active
      group by w.id
      having count(*) filter (where a.status in ('present','half_day') and a.attendance_date > current_date - 30) >= 3
         and coalesce((select max(payment_date) from wage_records g where g.worker_id = w.id and g.employer_id = v_emp), '1900-01-01')
             < current_date - 15
    ) t), '[]'::jsonb));
end; $$;

-- ---- Live Informal Wage Index (admin): avg daily wage by skill & state ----
create or replace function admin_wage_index(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return jsonb_build_object(
    'by_skill', coalesce((select jsonb_agg(row_to_json(t) order by t.avg_wage desc) from (
      select s.skill::text as skill, round(avg(e.daily_wage))::int as avg_wage, count(distinct e.worker_id) as workers
      from engagements e join worker_skills s on s.worker_id = e.worker_id
      where e.daily_wage is not null group by s.skill having count(*) > 0) t), '[]'::jsonb),
    'by_state', coalesce((select jsonb_agg(row_to_json(t) order by t.avg_wage desc) from (
      select coalesce(w.state,'Unknown') as state, round(avg(e.daily_wage))::int as avg_wage, count(distinct e.worker_id) as workers
      from engagements e join workers w on w.id = e.worker_id
      where e.daily_wage is not null group by w.state) t), '[]'::jsonb),
    'overall_avg', (select round(avg(daily_wage))::int from engagements where daily_wage is not null));
end; $$;

-- ---- Employer profile update (onboarding for real signups) ----
create or replace function emp_update_profile(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; e employers;
begin
  v_emp := _employer_id(p_token);
  update employers set
    full_name     = coalesce(nullif(p_payload->>'full_name',''), full_name),
    company_name  = coalesce(nullif(p_payload->>'company_name',''), company_name),
    business_type = coalesce(nullif(p_payload->>'business_type',''), business_type),
    district      = coalesce(nullif(p_payload->>'district',''), district),
    state         = coalesce(nullif(p_payload->>'state',''), state),
    updated_at    = now()
  where id = v_emp returning * into e;
  return to_jsonb(e);
end; $$;

-- grants
grant execute on function public.emp_update_profile(text, jsonb) to anon, authenticated;
grant execute on function public.demo_tamper(text, boolean) to anon, authenticated;
grant execute on function public.pub_ledger(text) to anon, authenticated;
grant execute on function public.emp_recent_activity(text) to anon, authenticated;
grant execute on function public.emp_alerts(text) to anon, authenticated;
grant execute on function public.admin_wage_index(text) to anon, authenticated;
