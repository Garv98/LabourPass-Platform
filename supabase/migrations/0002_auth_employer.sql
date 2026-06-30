-- ============================================================
-- Sessions, auth, SMS helper, employer-facing RPCs
-- All RPCs are SECURITY DEFINER and validate a custom session
-- token internally; the anon role can call them but cannot touch
-- tables directly (RLS locks everything — see 0004).
-- ============================================================

create sequence if not exists cert_seq start 1;

-- ---- session helpers ----
create or replace function _employer_id(p_token text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  select actor_id into v from sessions
   where token_hash = encode(extensions.digest(p_token,'sha256'),'hex')
     and actor_type = 'employer' and expires_at > now();
  if v is null then raise exception 'UNAUTHORIZED'; end if;
  return v;
end; $$;

create or replace function _admin_id(p_token text) returns uuid
language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  select actor_id into v from sessions
   where token_hash = encode(extensions.digest(p_token,'sha256'),'hex')
     and actor_type = 'admin' and expires_at > now();
  if v is null then raise exception 'UNAUTHORIZED'; end if;
  return v;
end; $$;

-- ---- simulated SMS gateway: send == insert + Realtime ----
create or replace function _send_sms(p_phone text, p_message text, p_lang language_code,
                                     p_ref_type text, p_ref_id uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  insert into sms_logs(direction, phone, message, language, status, reference_type, reference_id, delivered_at)
  values ('outbound', p_phone, p_message, coalesce(p_lang,'hi'), 'delivered', p_ref_type, p_ref_id, now())
  returning id into v;
  return v;
end; $$;

-- ============================================================
-- AUTH
-- ============================================================
create or replace function otp_send(p_phone text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_code text; v_count int;
begin
  if p_phone !~ '^[0-9]{10}$' then raise exception 'INVALID_PHONE'; end if;
  select count(*) into v_count from otp_requests where phone = p_phone and created_at > now() - interval '1 hour';
  if v_count >= 5 then raise exception 'RATE_LIMITED'; end if;
  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');  -- prod: crypto-random
  insert into otp_requests(phone, otp_hash, expires_at)
    values (p_phone, encode(extensions.digest(v_code,'sha256'),'hex'), now() + interval '5 minutes');
  perform _send_sms(p_phone, 'LabourPass OTP: ' || v_code || '. Valid 5 min. Kisi ko na batayein.', 'hi', 'otp', null);
  return jsonb_build_object('sent', true, 'expires_in', 300);
end; $$;

create or replace function otp_verify(p_phone text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_otp otp_requests; v_emp employers; v_token text;
begin
  select * into v_otp from otp_requests
    where phone = p_phone and is_used = false and expires_at > now()
    order by created_at desc limit 1;
  if v_otp.id is null then raise exception 'OTP_EXPIRED'; end if;
  if v_otp.attempt_count >= 3 then raise exception 'OTP_LOCKED'; end if;
  if v_otp.otp_hash <> encode(extensions.digest(p_code,'sha256'),'hex') then
    update otp_requests set attempt_count = attempt_count + 1 where id = v_otp.id;
    raise exception 'OTP_INVALID';
  end if;
  update otp_requests set is_used = true where id = v_otp.id;

  select * into v_emp from employers where phone = p_phone;
  if v_emp.id is null then
    insert into employers(phone, full_name, status)
      values (p_phone, 'Employer ' || right(p_phone,4), 'approved')   -- demo: auto-approve new signups
      returning * into v_emp;
  end if;
  if v_emp.status = 'suspended' then raise exception 'SUSPENDED'; end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into sessions(token_hash, actor_type, actor_id, expires_at)
    values (encode(extensions.digest(v_token,'sha256'),'hex'), 'employer', v_emp.id, now() + interval '12 hours');
  return jsonb_build_object('token', v_token, 'employer', to_jsonb(v_emp));
end; $$;

create or replace function admin_login(p_email text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin admin_users; v_token text;
begin
  select * into v_admin from admin_users where email = lower(p_email) and is_active;
  if v_admin.id is null or v_admin.password_hash <> extensions.crypt(p_password, v_admin.password_hash) then
    raise exception 'INVALID_CREDENTIALS';
  end if;
  update admin_users set last_login_at = now() where id = v_admin.id;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into sessions(token_hash, actor_type, actor_id, expires_at)
    values (encode(extensions.digest(v_token,'sha256'),'hex'), 'admin', v_admin.id, now() + interval '8 hours');
  return jsonb_build_object('token', v_token,
    'admin', jsonb_build_object('id', v_admin.id, 'email', v_admin.email, 'full_name', v_admin.full_name));
end; $$;

create or replace function app_logout(p_token text) returns void
language sql security definer set search_path = public, extensions as $$
  delete from sessions where token_hash = encode(extensions.digest(p_token,'sha256'),'hex');
$$;

-- ============================================================
-- EMPLOYER RPCs
-- ============================================================
create or replace function emp_me(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; e employers;
        v_active_today int; v_month_wage numeric;
begin
  v_emp := _employer_id(p_token);
  select * into e from employers where id = v_emp;
  select count(*) into v_active_today from attendance_records
    where employer_id = v_emp and attendance_date = current_date and status in ('present','half_day');
  select coalesce(sum(amount),0) into v_month_wage from wage_records
    where employer_id = v_emp and payment_date >= date_trunc('month', current_date);
  return jsonb_build_object(
    'employer', to_jsonb(e),
    'stats', jsonb_build_object(
      'total_workers', (select count(distinct worker_id) from engagements where employer_id = v_emp and is_active),
      'active_today', v_active_today,
      'month_wages', v_month_wage,
      'trust_score', e.trust_score
    ));
end; $$;

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
    -- phone already exists: update name/details from this registration (last-writer-wins)
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
    exception when invalid_text_representation then null;  -- skip non-enum skill
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

create or replace function emp_list_workers(p_token text, p_search text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((
    select jsonb_agg(row_to_json(t)) from (
      select w.id, w.public_id, w.full_name, w.phone, w.preferred_language,
             (select array_agg(skill::text) from worker_skills s where s.worker_id = w.id) as skills,
             e.id as engagement_id, e.daily_wage, e.role_title, e.worksite_id,
             (select count(*) from attendance_records a
                where a.worker_id = w.id and a.employer_id = v_emp
                  and a.attendance_date >= date_trunc('month', current_date) and a.status in ('present','half_day')) as days_this_month,
             (select max(payment_date) from wage_records g where g.worker_id = w.id and g.employer_id = v_emp) as last_wage_date
      from engagements e join workers w on w.id = e.worker_id
      where e.employer_id = v_emp and e.is_active
        and (p_search is null or w.full_name ilike '%'||p_search||'%' or w.phone like '%'||p_search||'%')
      group by w.id, e.id
      order by w.full_name
    ) t), '[]'::jsonb);
end; $$;

create or replace function emp_worker_detail(p_token text, p_worker uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; w workers;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where employer_id = v_emp and worker_id = p_worker) then
    raise exception 'NOT_FOUND'; end if;
  select * into w from workers where id = p_worker;
  return jsonb_build_object(
    'worker', to_jsonb(w),
    'skills', coalesce((select jsonb_agg(skill::text) from worker_skills where worker_id = p_worker), '[]'::jsonb),
    'attendance', coalesce((select jsonb_agg(row_to_json(a) order by a.attendance_date desc) from (
        select attendance_date, status, worksite_id from attendance_records
        where worker_id = p_worker and attendance_date >= current_date - 90) a), '[]'::jsonb),
    'wages', coalesce((select jsonb_agg(row_to_json(g) order by g.payment_date desc) from (
        select id, payment_date, amount, payment_mode, period_from, period_to, days_covered,
               (select full_name from employers e where e.id = wage_records.employer_id) as employer_name
        from wage_records where worker_id = p_worker order by payment_date desc limit 12) g), '[]'::jsonb),
    'certificates', coalesce((select jsonb_agg(row_to_json(c)) from (
        select certificate_no, role_title, start_date, end_date, is_revoked from experience_certificates
        where worker_id = p_worker) c), '[]'::jsonb)
  );
end; $$;

create or replace function emp_create_worksite(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; ws_row worksites;
begin
  v_emp := _employer_id(p_token);
  insert into worksites(employer_id, name, address, district, state, project_type, start_date)
  values (v_emp, p_payload->>'name', p_payload->>'address', p_payload->>'district', p_payload->>'state',
          p_payload->>'project_type', nullif(p_payload->>'start_date','')::date)
  returning * into ws_row;
  return to_jsonb(ws_row);
end; $$;

create or replace function emp_list_worksites(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select s.id, s.name, s.district, s.state, s.project_type, s.is_active,
           (select count(distinct e.worker_id) from engagements e where e.worksite_id = s.id and e.is_active) as worker_count
    from worksites s where s.employer_id = v_emp order by s.created_at desc) t), '[]'::jsonb);
end; $$;

-- roster for attendance UI: workers at a worksite with their status on a date
create or replace function emp_attendance_sheet(p_token text, p_worksite uuid, p_date date) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select w.id as worker_id, w.full_name, w.public_id, e.role_title,
           (select array_agg(skill::text) from worker_skills s where s.worker_id = w.id) as skills,
           (select status::text from attendance_records a
             where a.engagement_id = e.id and a.attendance_date = p_date) as status
    from engagements e join workers w on w.id = e.worker_id
    where e.employer_id = v_emp and e.is_active
      and (p_worksite is null or e.worksite_id = p_worksite)
    order by w.full_name) t), '[]'::jsonb);
end; $$;

-- bulk mark; first-mark-per-day wins (keeps hash chain honest)
create or replace function emp_mark_attendance(p_token text, p_worksite uuid, p_date date, p_records jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; r jsonb; v_eng engagements; v_w workers; v_marked int := 0; v_sms int := 0; v_status attendance_status;
begin
  v_emp := _employer_id(p_token);
  for r in select jsonb_array_elements(p_records) loop
    v_status := (r->>'status')::attendance_status;
    select * into v_eng from engagements
      where employer_id = v_emp and worker_id = (r->>'worker_id')::uuid
        and (p_worksite is null or worksite_id = p_worksite) and is_active limit 1;
    if v_eng.id is null then continue; end if;
    begin
      insert into attendance_records(engagement_id, employer_id, worker_id, worksite_id, attendance_date, status, marked_by, sms_sent)
      values (v_eng.id, v_emp, v_eng.worker_id, v_eng.worksite_id, p_date, v_status, v_emp,
              v_status in ('present','half_day'));
      v_marked := v_marked + 1;
      if v_status in ('present','half_day') then
        select * into v_w from workers where id = v_eng.worker_id;
        perform _send_sms(v_w.phone,
          case when v_w.preferred_language='en'
            then 'LabourPass Attendance: '||to_char(p_date,'DD-Mon')||' marked '||v_status::text||
                 '. Wrong? Reply DISPUTE '||to_char(p_date,'DD-Mon')
            else 'LabourPass Haazri: '||to_char(p_date,'DD-Mon')||' ko haazri darj ('||v_status::text||
                 '). Galat lage to DISPUTE '||to_char(p_date,'DD-Mon')||' bhejein.'
          end, v_w.preferred_language, 'attendance', null);
        v_sms := v_sms + 1;
      end if;
    exception when unique_violation then null;  -- already marked this day
    end;
  end loop;
  return jsonb_build_object('marked', v_marked, 'sms_queued', v_sms);
end; $$;

create or replace function emp_record_wage(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_wage wage_records; v_w workers; v_ref text;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where id = (p_payload->>'engagement_id')::uuid and employer_id = v_emp) then
    raise exception 'NOT_FOUND'; end if;

  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode,
                          period_from, period_to, days_covered, reference_no, notes, idempotency_key, sms_sent)
  values ((p_payload->>'engagement_id')::uuid, v_emp, (p_payload->>'worker_id')::uuid,
          (p_payload->>'payment_date')::date, (p_payload->>'amount')::numeric,
          coalesce((p_payload->>'payment_mode')::payment_mode,'cash'),
          nullif(p_payload->>'period_from','')::date, nullif(p_payload->>'period_to','')::date,
          nullif(p_payload->>'days_covered','')::smallint, p_payload->>'reference_no', p_payload->>'notes',
          p_payload->>'idempotency_key', true)
  on conflict (idempotency_key) do nothing
  returning * into v_wage;

  if v_wage.id is null then
    select * into v_wage from wage_records where idempotency_key = p_payload->>'idempotency_key';
    return jsonb_build_object('wage_record', to_jsonb(v_wage), 'duplicate', true);
  end if;

  v_ref := 'LP-W-'||to_char(v_wage.created_at,'YYYYMMDD')||'-'||substr(v_wage.id::text,1,4);
  update wage_records set reference_no = coalesce(reference_no, v_ref) where id = v_wage.id;

  select * into v_w from workers where id = v_wage.worker_id;
  perform _send_sms(v_w.phone,
    case when v_w.preferred_language='en'
      then 'LabourPass Wage Receipt: Rs.'||v_wage.amount||' from '||(select full_name from employers where id=v_emp)||
           ' on '||to_char(v_wage.payment_date,'DD-Mon')||' via '||v_wage.payment_mode::text||'. Ref: '||v_ref
      else 'LabourPass Wage Receipt: Rs.'||v_wage.amount||' '||(select full_name from employers where id=v_emp)||
           ' se mila '||to_char(v_wage.payment_date,'DD-Mon')||' ko '||v_wage.payment_mode::text||' dwara. Ref: '||v_ref
    end, v_w.preferred_language, 'wage', v_wage.id);

  insert into trust_ratings(wage_record_id, employer_id, worker_id)
    values (v_wage.id, v_emp, v_wage.worker_id) on conflict do nothing;

  insert into audit_logs(actor_id, actor_type, action, table_name, record_id, new_values)
    values (v_emp, 'employer', 'wage.create', 'wage_records', v_wage.id,
            jsonb_build_object('amount', v_wage.amount, 'worker_id', v_wage.worker_id));

  return jsonb_build_object('wage_record', to_jsonb(v_wage), 'ref', v_ref, 'sms_queued', true);
end; $$;

create or replace function emp_send_trust_sms(p_token text, p_wage uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_wage wage_records; v_w workers;
begin
  v_emp := _employer_id(p_token);
  select * into v_wage from wage_records where id = p_wage and employer_id = v_emp;
  if v_wage.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_w from workers where id = v_wage.worker_id;
  perform _send_sms(v_w.phone,
    case when v_w.preferred_language='en'
      then 'LabourPass: Did you receive full payment Rs.'||v_wage.amount||' from '||
           (select full_name from employers where id=v_emp)||'? Reply 1=Yes 2=No'
      else 'LabourPass: Kya aapko '||(select full_name from employers where id=v_emp)||
           ' se poori payment Rs.'||v_wage.amount||' mili? 1=Haan 2=Nahi bhejein.'
    end, v_w.preferred_language, 'trust', v_wage.id);
  update trust_ratings set sms_sent_at = now() where wage_record_id = p_wage and worker_id = v_wage.worker_id;
  update wage_records set trust_sms_sent = true where id = p_wage;
  return jsonb_build_object('sent', true);
end; $$;

create or replace function emp_issue_certificate(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_cert experience_certificates; v_w workers; v_no text; v_days int;
begin
  v_emp := _employer_id(p_token);
  if not exists (select 1 from engagements where id = (p_payload->>'engagement_id')::uuid and employer_id = v_emp) then
    raise exception 'NOT_FOUND'; end if;
  v_no := 'LP-CERT-'||to_char(now(),'YYYY')||'-'||lpad(nextval('cert_seq')::text, 6, '0');
  select count(*) into v_days from attendance_records
    where worker_id = (p_payload->>'worker_id')::uuid and employer_id = v_emp
      and status in ('present','half_day')
      and attendance_date between (p_payload->>'start_date')::date and (p_payload->>'end_date')::date;

  insert into experience_certificates(certificate_no, engagement_id, employer_id, worker_id, role_title,
    skills_certified, worksite_name, start_date, end_date, total_days, conduct_remarks, issued_by)
  values (v_no, (p_payload->>'engagement_id')::uuid, v_emp, (p_payload->>'worker_id')::uuid, p_payload->>'role_title',
    array(select jsonb_array_elements_text(coalesce(p_payload->'skills','[]'::jsonb))),
    p_payload->>'worksite_name', (p_payload->>'start_date')::date, (p_payload->>'end_date')::date,
    v_days, p_payload->>'conduct_remarks', p_payload->>'issued_by')
  returning * into v_cert;

  select * into v_w from workers where id = v_cert.worker_id;
  perform _send_sms(v_w.phone,
    'LabourPass Certificate: '||(select full_name from employers where id=v_emp)||' ne jari kiya. No: '||
    v_no||'. Verify: /verify/cert/'||v_no, v_w.preferred_language, 'certificate', v_cert.id);
  return to_jsonb(v_cert);
end; $$;

create or replace function emp_list_certificates(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.issued_at desc) from (
    select c.certificate_no, c.role_title, c.start_date, c.end_date, c.is_revoked, c.issued_at,
           w.full_name as worker_name from experience_certificates c
    join workers w on w.id = c.worker_id where c.employer_id = v_emp) t), '[]'::jsonb);
end; $$;

create or replace function emp_list_wages(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.payment_date desc) from (
    select g.id, g.payment_date, g.amount, g.payment_mode, g.reference_no, g.trust_sms_sent,
           w.full_name as worker_name, w.public_id from wage_records g
    join workers w on w.id = g.worker_id where g.employer_id = v_emp order by g.payment_date desc limit 100) t), '[]'::jsonb);
end; $$;

create or replace function emp_wage_analytics(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  return jsonb_build_object(
    'by_month', coalesce((select jsonb_agg(row_to_json(t)) from (
      select to_char(date_trunc('month', payment_date),'Mon YY') as month,
             sum(amount) as total, count(*) as payments
      from wage_records where employer_id = v_emp group by date_trunc('month', payment_date)
      order by date_trunc('month', payment_date)) t), '[]'::jsonb),
    'by_mode', coalesce((select jsonb_agg(row_to_json(t)) from (
      select payment_mode::text as mode, sum(amount) as total from wage_records
      where employer_id = v_emp group by payment_mode) t), '[]'::jsonb),
    'total_disbursed', (select coalesce(sum(amount),0) from wage_records where employer_id = v_emp));
end; $$;

create or replace function emp_trust_summary(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; e employers;
begin
  v_emp := _employer_id(p_token);
  select * into e from employers where id = v_emp;
  return jsonb_build_object(
    'score', e.trust_score,
    'total_ratings', (select count(*) from trust_ratings where employer_id = v_emp and responded_at is not null and is_valid),
    'positive', (select count(*) from trust_ratings where employer_id = v_emp and rating = 1 and is_valid),
    'negative', (select count(*) from trust_ratings where employer_id = v_emp and rating = 2 and is_valid),
    'trend', coalesce((select jsonb_agg(row_to_json(t)) from (
      select to_char(date_trunc('month', responded_at),'Mon YY') as month,
             round(100.0 * sum((rating=1)::int) / nullif(count(*),0), 0) as score
      from trust_ratings where employer_id = v_emp and responded_at is not null and is_valid
      group by date_trunc('month', responded_at) order by date_trunc('month', responded_at)) t), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(row_to_json(t)) from (
      select to_char(responded_at,'DD Mon') as date, rating,
             'XXXXXX'||right((select phone from workers w where w.id = tr.worker_id),4) as worker
      from trust_ratings tr where employer_id = v_emp and responded_at is not null
      order by responded_at desc limit 10) t), '[]'::jsonb));
end; $$;
