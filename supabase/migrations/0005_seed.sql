-- ============================================================
-- DEMO SEED  (idempotent-ish: safe to run on a fresh DB)
-- Admin:    admin@labourpass.in / admin123
-- Employer: login with phone 9876543210, OTP shows on /phone panel
-- Memorable passbook link: /verify/passbook/LP-SUN001
-- ============================================================
do $$
declare
  v_admin uuid; v_empA uuid; v_empB uuid; v_empC uuid; v_wsA uuid;
  v_sunita uuid; v_raju uuid; v_meera uuid; v_kishan uuid;
  v_anil uuid; v_farida uuid; v_gopal uuid; v_lakshmi uuid; v_testc uuid;
  v_eng_sunita uuid; v_eng_raju uuid; v_engC uuid;
  v_wage uuid; d date; i int;
begin
  -- Idempotent: skip if already seeded (so full_setup.sql is safe to re-run).
  if exists (select 1 from employers where phone = '9876543210') then
    raise notice 'Seed already present, skipping.';
    return;
  end if;

  -- ---------- admin ----------
  insert into admin_users(email, password_hash, full_name)
  values ('admin@labourpass.in', extensions.crypt('admin123', extensions.gen_salt('bf')), 'Priya Menon')
  on conflict (email) do nothing returning id into v_admin;
  if v_admin is null then select id into v_admin from admin_users where email = 'admin@labourpass.in'; end if;

  -- ---------- employers ----------
  insert into employers(phone, full_name, company_name, business_type, district, state, status, approved_by, approved_at)
  values ('9876543210','Ramesh Kumar','Ramesh Kumar Construction','construction','Bengaluru','Karnataka','approved',v_admin,now())
  returning id into v_empA;
  insert into employers(phone, full_name, company_name, business_type, district, state, status)
  values ('9876500000','Suresh Patil','Suresh Builders','construction','Pune','Maharashtra','pending')
  returning id into v_empB;
  insert into employers(phone, full_name, company_name, business_type, district, state, status, approved_by, approved_at)
  values ('9876511111','Mishra Contractors','Mishra Contractors','construction','Lucknow','Uttar Pradesh','approved',v_admin,now())
  returning id into v_empC;

  -- ---------- worksite ----------
  insert into worksites(employer_id, name, district, state, project_type, start_date)
  values (v_empA,'MG Road Project','Bengaluru','Karnataka','commercial', current_date - 90)
  returning id into v_wsA;

  -- ---------- workers ----------
  insert into workers(public_id, phone, full_name, father_name, gender, state, district, preferred_language, registered_by, is_verified)
  values ('LP-SUN001','9000000001','Sunita Devi','Ram Prasad','female','Bihar','Saharsa','hi',v_empA,true) returning id into v_sunita;
  insert into workers(public_id, phone, full_name, gender, state, district, registered_by, is_verified)
  values ('LP-RAJ001','9000000002','Raju Sharma','male','Bihar','Patna',v_empA,true) returning id into v_raju;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000003','Meera Bai','female','Karnataka',v_empA,true) returning id into v_meera;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000004','Kishan Lal','male','Karnataka',v_empA,true) returning id into v_kishan;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000005','Anil Yadav','male','UP',v_empA,true) returning id into v_anil;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000006','Farida Begum','female','WB',v_empA,true) returning id into v_farida;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000007','Gopal Mehta','male','Rajasthan',v_empA,true) returning id into v_gopal;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000008','Lakshmi N','female','Tamil Nadu',v_empA,true) returning id into v_lakshmi;
  insert into workers(phone, full_name, gender, state, registered_by, is_verified)
  values ('9000000099','Test Worker C','male','UP',v_empC,true) returning id into v_testc;

  -- ---------- skills ----------
  insert into worker_skills(worker_id, skill, added_by) values
    (v_sunita,'mason',v_empA),(v_sunita,'helper',v_empA),
    (v_raju,'mason',v_empA),(v_meera,'helper',v_empA),(v_kishan,'electrician',v_empA),
    (v_anil,'plumber',v_empA),(v_farida,'painter',v_empA),(v_gopal,'carpenter',v_empA),
    (v_lakshmi,'domestic_worker',v_empA)
  on conflict do nothing;

  -- ---------- engagements ----------
  insert into engagements(employer_id, worker_id, worksite_id, daily_wage, role_title, start_date) values
    (v_empA,v_sunita,v_wsA,450,'Senior Mason', current_date-90) returning id into v_eng_sunita;
  insert into engagements(employer_id, worker_id, worksite_id, daily_wage, role_title, start_date) values
    (v_empA,v_raju,v_wsA,400,'Mason', current_date-75) returning id into v_eng_raju;
  insert into engagements(employer_id, worker_id, worksite_id, daily_wage, role_title) values
    (v_empA,v_meera,v_wsA,300,'Helper'),(v_empA,v_kishan,v_wsA,500,'Electrician'),
    (v_empA,v_anil,v_wsA,480,'Plumber'),(v_empA,v_farida,v_wsA,350,'Painter'),
    (v_empA,v_gopal,v_wsA,460,'Carpenter'),(v_empA,v_lakshmi,v_wsA,320,'Domestic');
  insert into engagements(employer_id, worker_id, daily_wage, role_title) values
    (v_empC,v_testc,400,'Helper') returning id into v_engC;
  update employers set total_workers = 8 where id = v_empA;

  -- ---------- attendance (Sunita + Raju, last ~45 days, hash-chained) ----------
  -- single-row inserts so the BEFORE-INSERT hash trigger reliably chains each row.
  for d in select generate_series(current_date - 45, current_date - 1, interval '1 day')::date loop
    insert into attendance_records(engagement_id, employer_id, worker_id, worksite_id, attendance_date, status, marked_by, sms_sent)
    values (v_eng_sunita, v_empA, v_sunita, v_wsA, d,
      (case when extract(dow from d) = 0 then 'absent'
            when random() < 0.08 then 'half_day' else 'present' end)::attendance_status, v_empA, false);
  end loop;
  for d in select generate_series(current_date - 40, current_date - 1, interval '1 day')::date loop
    insert into attendance_records(engagement_id, employer_id, worker_id, worksite_id, attendance_date, status, marked_by, sms_sent)
    values (v_eng_raju, v_empA, v_raju, v_wsA, d,
      (case when extract(dow from d) = 0 then 'absent'
            when random() < 0.12 then 'absent' else 'present' end)::attendance_status, v_empA, false);
  end loop;

  -- ---------- wages (single-row inserts; hash-chained) ----------
  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, period_from, period_to, days_covered, reference_no, sms_sent)
    values (v_eng_sunita,v_empA,v_sunita, current_date-62, 9450,'upi',  current_date-92, current_date-62, 21,'LP-W-001',true);
  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, period_from, period_to, days_covered, reference_no, sms_sent)
    values (v_eng_sunita,v_empA,v_sunita, current_date-32, 8550,'cash', current_date-61, current_date-32, 19,'LP-W-002',true);
  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, period_from, period_to, days_covered, reference_no, sms_sent)
    values (v_eng_sunita,v_empA,v_sunita, current_date-2,  9000,'cash', current_date-31, current_date-2,  20,'LP-W-003',true);
  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, days_covered, sms_sent)
    values (v_eng_raju,v_empA,v_raju, current_date-30, 8000,'cash', 20, true);
  insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, days_covered, sms_sent)
    values (v_eng_raju,v_empA,v_raju, current_date-1,  7600,'upi',  19, true);

  -- ---------- trust ratings: empA mostly positive (Verified Payer) ----------
  for v_wage in select id from wage_records where employer_id = v_empA loop
    insert into trust_ratings(wage_record_id, employer_id, worker_id, rating, sms_sent_at, responded_at, response_raw)
    select id, employer_id, worker_id, 1, created_at, created_at + interval '2 hours', '1'
    from wage_records where id = v_wage on conflict do nothing;
  end loop;
  -- one negative for realism
  update trust_ratings set rating = 2, response_raw = '2'
    where id = (select tr.id from trust_ratings tr join wage_records w on w.id = tr.wage_record_id
                where tr.employer_id = v_empA order by w.payment_date asc limit 1);

  -- ---------- empC low-trust scenario ----------
  for i in 1..5 loop
    insert into wage_records(engagement_id, employer_id, worker_id, payment_date, amount, payment_mode, days_covered, sms_sent)
    values (v_engC, v_empC, v_testc, current_date - (i*5), 6000,'cash', 15, true) returning id into v_wage;
    insert into trust_ratings(wage_record_id, employer_id, worker_id, rating, sms_sent_at, responded_at, response_raw)
    values (v_wage, v_empC, v_testc, case when i <= 3 then 2 else 1 end, now(), now(), case when i <= 3 then '2' else '1' end);
  end loop;

  -- ---------- certificate (Sunita) ----------
  insert into experience_certificates(certificate_no, engagement_id, employer_id, worker_id, role_title,
    skills_certified, worksite_name, start_date, end_date, total_days, conduct_remarks, issued_by)
  values ('LP-CERT-' || to_char(now(),'YYYY') || '-000001', v_eng_sunita, v_empA, v_sunita, 'Senior Mason',
    array['mason','helper'], 'MG Road Project', current_date - 90, current_date - 1, 58, 'Excellent, reliable worker.', 'Ramesh Kumar');

  -- ---------- one open dispute ----------
  insert into disputes(worker_id, employer_id, dispute_type, description, reported_via, status)
  values (v_meera, v_empA, 'wage', 'WAGEDISPUTE 2000 - kam paisa mila', 'sms', 'open');

  -- recompute scores
  perform recompute_trust(v_empA);
  perform recompute_trust(v_empC);

  raise notice 'Seed done. Admin admin@labourpass.in/admin123 | Employer phone 9876543210 | Passbook LP-SUN001';
end $$;
