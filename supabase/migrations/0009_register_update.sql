-- ============================================================
-- Patch: when registering an existing phone, UPDATE the worker's
-- name/details (last-writer-wins) instead of silently keeping the
-- old record. Run this file alone in the SQL editor.
-- ============================================================
create or replace function emp_register_worker(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_worker workers; v_eng engagements;
        v_phone text; v_skill text; v_lang language_code;
begin
  v_emp := _employer_id(p_token);
  v_phone := p_payload->>'phone';
  if v_phone !~ '^[0-9]{10}$' then raise exception 'INVALID_PHONE'; end if;
  v_lang := coalesce((p_payload->>'preferred_language')::language_code, 'hi');

  select * into v_worker from workers where phone = v_phone;
  if v_worker.id is null then
    insert into workers(phone, full_name, father_name, date_of_birth, gender, aadhaar_last4,
                        address, state, district, preferred_language, registered_by, is_verified)
    values (v_phone, p_payload->>'full_name', p_payload->>'father_name',
            nullif(p_payload->>'date_of_birth','')::date, p_payload->>'gender', p_payload->>'aadhaar_last4',
            p_payload->>'address', p_payload->>'state', p_payload->>'district', v_lang, v_emp, true)
    returning * into v_worker;
  else
    update workers set
      full_name          = coalesce(nullif(p_payload->>'full_name',''), full_name),
      father_name        = coalesce(nullif(p_payload->>'father_name',''), father_name),
      date_of_birth      = coalesce(nullif(p_payload->>'date_of_birth','')::date, date_of_birth),
      gender             = coalesce(nullif(p_payload->>'gender',''), gender),
      aadhaar_last4      = coalesce(nullif(p_payload->>'aadhaar_last4',''), aadhaar_last4),
      address            = coalesce(nullif(p_payload->>'address',''), address),
      state              = coalesce(nullif(p_payload->>'state',''), state),
      district           = coalesce(nullif(p_payload->>'district',''), district),
      preferred_language = coalesce(nullif(p_payload->>'preferred_language','')::language_code, preferred_language),
      updated_at         = now()
    where id = v_worker.id
    returning * into v_worker;
  end if;

  for v_skill in select jsonb_array_elements_text(coalesce(p_payload->'skills','[]'::jsonb)) loop
    begin
      insert into worker_skills(worker_id, skill, added_by) values (v_worker.id, v_skill::worker_skill, v_emp)
      on conflict (worker_id, skill) do nothing;
    exception when invalid_text_representation then null;
    end;
  end loop;

  insert into engagements(employer_id, worker_id, worksite_id, daily_wage, role_title)
  values (v_emp, v_worker.id, nullif(p_payload->>'worksite_id','')::uuid,
          nullif(p_payload->>'daily_wage','')::numeric, p_payload->>'role_title')
  on conflict (employer_id, worker_id, worksite_id) do update set is_active = true
  returning * into v_eng;

  update employers set total_workers = (select count(distinct worker_id) from engagements where employer_id = v_emp and is_active)
    where id = v_emp;

  perform _send_sms(v_phone,
    case when v_lang = 'en'
      then 'LabourPass: Hello ' || v_worker.full_name || '! You are registered by ' ||
           (select full_name from employers where id = v_emp) || '. ID: ' || v_worker.public_id || '. Text PROFILE for details.'
      else 'LabourPass: Namaste ' || v_worker.full_name || '! ' ||
           (select full_name from employers where id = v_emp) || ' ne aapko register kiya. ID: ' ||
           v_worker.public_id || '. Jankari ke liye PROFILE bhejein.'
    end, v_lang, 'worker', v_worker.id);

  insert into audit_logs(actor_id, actor_type, action, table_name, record_id, new_values)
    values (v_emp, 'employer', 'worker.register', 'workers', v_worker.id, jsonb_build_object('phone', v_phone));

  return jsonb_build_object('worker', to_jsonb(v_worker), 'engagement_id', v_eng.id, 'sms_queued', true);
end; $$;
