-- ============================================================
-- Personalised worker language (Phase 4).
-- Effective language = explicit preferred_language → region (state)
-- → English. Messages live in a templates table with {{var}}
-- substitution and automatic English fallback. Run this file alone.
-- NOTE: regional translations are machine-generated — verify before
-- a production launch. English is always the safe fallback.
-- ============================================================

-- New workers default to "auto" (null) so the region/English logic applies.
alter table workers alter column preferred_language drop default;

-- ---- region → language ----
create or replace function region_language(p_state text) returns language_code
language sql immutable as $$
  select case lower(trim(coalesce(p_state,'')))
    when 'west bengal' then 'bn' when 'wb' then 'bn'
    when 'tamil nadu' then 'ta' when 'tamilnadu' then 'ta'
    when 'telangana' then 'te' when 'andhra pradesh' then 'te' when 'ap' then 'te'
    when 'karnataka' then 'kn'
    when 'maharashtra' then 'mr'
    when 'gujarat' then 'gu'
    when 'odisha' then 'or' when 'orissa' then 'or'
    when 'bihar' then 'hi' when 'uttar pradesh' then 'hi' when 'up' then 'hi'
    when 'madhya pradesh' then 'hi' when 'mp' then 'hi' when 'rajasthan' then 'hi'
    when 'jharkhand' then 'hi' when 'haryana' then 'hi' when 'delhi' then 'hi'
    when 'chhattisgarh' then 'hi' when 'uttarakhand' then 'hi' when 'himachal pradesh' then 'hi'
    else 'en'
  end::language_code
$$;

create or replace function effective_lang(p_pref language_code, p_state text) returns language_code
language sql immutable as $$
  select coalesce(p_pref, region_language(p_state))
$$;

-- ---- templates ----
create table if not exists message_templates (
  key  text not null,
  lang language_code not null,
  body text not null,
  primary key (key, lang)
);

create or replace function render_msg(p_key text, p_lang language_code, p_vars jsonb default '{}'::jsonb) returns text
language plpgsql stable as $$
declare v_body text; k text;
begin
  select body into v_body from message_templates where key = p_key and lang = p_lang;
  if v_body is null then select body into v_body from message_templates where key = p_key and lang = 'en'; end if;
  if v_body is null then return ''; end if;
  for k in select jsonb_object_keys(p_vars) loop
    v_body := replace(v_body, '{{' || k || '}}', coalesce(p_vars->>k, ''));
  end loop;
  return v_body;
end; $$;

insert into message_templates(key, lang, body) values
-- welcome
('welcome','en','LabourPass: Hello {{name}}! {{employer}} registered you. ID: {{id}}. Reply PROFILE for details.'),
('welcome','hi','LabourPass: नमस्ते {{name}}! {{employer}} ने आपको पंजीकृत किया। ID: {{id}}. जानकारी हेतु PROFILE भेजें।'),
('welcome','bn','LabourPass: নমস্কার {{name}}! {{employer}} আপনাকে নিবন্ধন করেছেন। ID: {{id}}. বিস্তারিত জানতে PROFILE পাঠান।'),
('welcome','ta','LabourPass: வணக்கம் {{name}}! {{employer}} உங்களைப் பதிவு செய்துள்ளார். ID: {{id}}. விவரங்களுக்கு PROFILE அனுப்பவும்.'),
('welcome','te','LabourPass: నమస్తే {{name}}! {{employer}} మిమ్మల్ని నమోదు చేశారు. ID: {{id}}. వివరాలకు PROFILE పంపండి.'),
('welcome','mr','LabourPass: नमस्कार {{name}}! {{employer}} यांनी तुमची नोंदणी केली. ID: {{id}}. माहितीसाठी PROFILE पाठवा.'),
('welcome','gu','LabourPass: નમસ્તે {{name}}! {{employer}} એ તમારી નોંધણી કરી. ID: {{id}}. વિગતો માટે PROFILE મોકલો.'),
('welcome','kn','LabourPass: ನಮಸ್ಕಾರ {{name}}! {{employer}} ನಿಮ್ಮನ್ನು ನೋಂದಾಯಿಸಿದ್ದಾರೆ. ID: {{id}}. ವಿವರಗಳಿಗೆ PROFILE ಕಳುಹಿಸಿ.'),
('welcome','or','LabourPass: ନମସ୍କାର {{name}}! {{employer}} ଆପଣଙ୍କୁ ପଞ୍ଜୀକରଣ କଲେ। ID: {{id}}. ବିବରଣୀ ପାଇଁ PROFILE ପଠାନ୍ତୁ।'),
-- attendance
('attendance','en','LabourPass Attendance: {{date}} marked {{status}}. Wrong? Reply DISPUTE {{date}}.'),
('attendance','hi','LabourPass हाज़िरी: {{date}} को {{status}} दर्ज। गलत? DISPUTE {{date}} भेजें।'),
('attendance','bn','LabourPass হাজিরা: {{date}} {{status}} নথিভুক্ত। ভুল? DISPUTE {{date}} পাঠান।'),
('attendance','ta','LabourPass வருகை: {{date}} {{status}} பதிவு. தவறா? DISPUTE {{date}} அனுப்பவும்.'),
('attendance','te','LabourPass హాజరు: {{date}} {{status}} నమోదు. తప్పా? DISPUTE {{date}} పంపండి.'),
('attendance','mr','LabourPass हजेरी: {{date}} रोजी {{status}} नोंद. चूक? DISPUTE {{date}} पाठवा.'),
('attendance','gu','LabourPass હાજરી: {{date}} {{status}} નોંધ. ખોટું? DISPUTE {{date}} મોકલો.'),
('attendance','kn','LabourPass ಹಾಜರಾತಿ: {{date}} {{status}} ದಾಖಲಾಗಿದೆ. ತಪ್ಪೇ? DISPUTE {{date}} ಕಳುಹಿಸಿ.'),
('attendance','or','LabourPass ହାଜିରା: {{date}} {{status}} ଦାଖଲ। ଭୁଲ? DISPUTE {{date}} ପଠାନ୍ତୁ।'),
-- wage receipt
('wage_receipt','en','LabourPass Receipt: Rs.{{amount}} from {{employer}} on {{date}} via {{mode}}. Ref: {{ref}}.'),
('wage_receipt','hi','LabourPass रसीद: {{employer}} से Rs.{{amount}} {{date}} को {{mode}} द्वारा मिला। Ref: {{ref}}.'),
('wage_receipt','bn','LabourPass রসিদ: {{employer}} থেকে Rs.{{amount}} {{date}} {{mode}} মাধ্যমে। Ref: {{ref}}.'),
('wage_receipt','ta','LabourPass ரசீது: {{employer}} இடமிருந்து Rs.{{amount}} {{date}} {{mode}} மூலம். Ref: {{ref}}.'),
('wage_receipt','te','LabourPass రసీదు: {{employer}} నుండి Rs.{{amount}} {{date}} {{mode}} ద్వారా. Ref: {{ref}}.'),
('wage_receipt','mr','LabourPass पावती: {{employer}} कडून Rs.{{amount}} {{date}} रोजी {{mode}} द्वारे. Ref: {{ref}}.'),
('wage_receipt','gu','LabourPass રસીદ: {{employer}} તરફથી Rs.{{amount}} {{date}} {{mode}} દ્વારા. Ref: {{ref}}.'),
('wage_receipt','kn','LabourPass ರಸೀದಿ: {{employer}} ರಿಂದ Rs.{{amount}} {{date}} {{mode}} ಮೂಲಕ. Ref: {{ref}}.'),
('wage_receipt','or','LabourPass ରସିଦ: {{employer}} ଠାରୁ Rs.{{amount}} {{date}} {{mode}} ମାଧ୍ୟମରେ। Ref: {{ref}}.'),
-- trust request
('trust_request','en','LabourPass: Did you get full payment Rs.{{amount}} from {{employer}}? Reply 1=Yes 2=No.'),
('trust_request','hi','LabourPass: क्या आपको {{employer}} से पूरा भुगतान Rs.{{amount}} मिला? 1=हाँ 2=नहीं भेजें।'),
('trust_request','bn','LabourPass: আপনি কি {{employer}} থেকে সম্পূর্ণ Rs.{{amount}} পেয়েছেন? 1=হ্যাঁ 2=না পাঠান।'),
('trust_request','ta','LabourPass: {{employer}} இடமிருந்து முழு Rs.{{amount}} பெற்றீர்களா? 1=ஆம் 2=இல்லை அனுப்பவும்.'),
('trust_request','te','LabourPass: {{employer}} నుండి పూర్తి Rs.{{amount}} అందిందా? 1=అవును 2=కాదు పంపండి.'),
('trust_request','mr','LabourPass: {{employer}} कडून पूर्ण Rs.{{amount}} मिळाले का? 1=होय 2=नाही पाठवा.'),
('trust_request','gu','LabourPass: {{employer}} તરફથી પૂરા Rs.{{amount}} મળ્યા? 1=હા 2=ના મોકલો.'),
('trust_request','kn','LabourPass: {{employer}} ರಿಂದ ಪೂರ್ಣ Rs.{{amount}} ಸಿಕ್ಕಿತೇ? 1=ಹೌದು 2=ಇಲ್ಲ ಕಳುಹಿಸಿ.'),
('trust_request','or','LabourPass: {{employer}} ଠାରୁ ସମ୍ପୂର୍ଣ୍ଣ Rs.{{amount}} ମିଳିଲା କି? 1=ହଁ 2=ନା ପଠାନ୍ତୁ।')
on conflict (key, lang) do update set body = excluded.body;

-- ============================================================
-- Rewire the worker-facing senders to use the templates.
-- ============================================================
create or replace function emp_register_worker(p_token text, p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid; v_worker workers; v_eng engagements;
        v_phone text; v_skill text; v_lang language_code;
begin
  v_emp := _employer_id(p_token);
  v_phone := p_payload->>'phone';
  if v_phone !~ '^[0-9]{10}$' then raise exception 'INVALID_PHONE'; end if;
  v_lang := nullif(p_payload->>'preferred_language','')::language_code;  -- null = auto (region/English)

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
      preferred_language = coalesce(v_lang, preferred_language),
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
    render_msg('welcome', effective_lang(v_worker.preferred_language, v_worker.state),
      jsonb_build_object('name', v_worker.full_name,
                         'employer', (select full_name from employers where id = v_emp),
                         'id', v_worker.public_id)),
    effective_lang(v_worker.preferred_language, v_worker.state), 'worker', v_worker.id);

  insert into audit_logs(actor_id, actor_type, action, table_name, record_id, new_values)
    values (v_emp, 'employer', 'worker.register', 'workers', v_worker.id, jsonb_build_object('phone', v_phone));

  return jsonb_build_object('worker', to_jsonb(v_worker), 'engagement_id', v_eng.id, 'sms_queued', true);
end; $$;

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
      values (v_eng.id, v_emp, v_eng.worker_id, v_eng.worksite_id, p_date, v_status, v_emp, v_status in ('present','half_day'));
      v_marked := v_marked + 1;
      if v_status in ('present','half_day') then
        select * into v_w from workers where id = v_eng.worker_id;
        perform _send_sms(v_w.phone,
          render_msg('attendance', effective_lang(v_w.preferred_language, v_w.state),
            jsonb_build_object('date', to_char(p_date,'DD-Mon'), 'status', v_status::text)),
          effective_lang(v_w.preferred_language, v_w.state), 'attendance', null);
        v_sms := v_sms + 1;
      end if;
    exception when unique_violation then null;
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
    render_msg('wage_receipt', effective_lang(v_w.preferred_language, v_w.state),
      jsonb_build_object('amount', v_wage.amount::text,
                         'employer', (select full_name from employers where id = v_emp),
                         'date', to_char(v_wage.payment_date,'DD-Mon'),
                         'mode', v_wage.payment_mode::text, 'ref', v_ref)),
    effective_lang(v_w.preferred_language, v_w.state), 'wage', v_wage.id);

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
    render_msg('trust_request', effective_lang(v_w.preferred_language, v_w.state),
      jsonb_build_object('amount', v_wage.amount::text,
                         'employer', (select full_name from employers where id = v_emp))),
    effective_lang(v_w.preferred_language, v_w.state), 'trust', v_wage.id);
  update trust_ratings set sms_sent_at = now() where wage_record_id = p_wage and worker_id = v_wage.worker_id;
  update wage_records set trust_sms_sent = true where id = p_wage;
  return jsonb_build_object('sent', true);
end; $$;
