-- ============================================================
-- Trust recompute, inbound SMS parser, public verify, admin RPCs
-- ============================================================

create or replace function recompute_trust(p_employer uuid) returns numeric
language plpgsql security definer set search_path = public, extensions as $$
declare v_total int; v_pos int; v_score numeric;
begin
  select count(*), count(*) filter (where rating = 1) into v_total, v_pos
    from trust_ratings
    where employer_id = p_employer and responded_at > now() - interval '90 days'
      and is_valid and rating is not null;
  if v_total = 0 then v_score := null; else v_score := round(100.0 * v_pos / v_total, 2); end if;
  update employers set trust_score = v_score where id = p_employer;
  if v_score is not null and v_score < 60 and v_total >= 3 then
    insert into notifications(recipient_id, recipient_type, title, body, link)
      select id, 'admin', 'Low trust score',
             (select full_name from employers where id = p_employer) || ' dropped to ' || v_score || '%', '/admin/trust'
      from admin_users where is_active;
  end if;
  return v_score;
end; $$;

-- ---- inbound SMS (called from /phone simulator; same parser real gateway would use) ----
create or replace function sms_inbound(p_sender text, p_body text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_w workers; v_body text; v_reply text; v_tr trust_ratings; v_disp uuid;
begin
  v_body := upper(trim(p_body));
  insert into sms_logs(direction, phone, message, status) values ('inbound', p_sender, p_body, 'received');
  select * into v_w from workers where phone = p_sender;
  if v_w.id is null then
    v_reply := 'LabourPass: Aap registered nahi hain. Apne employer se register karayein.';
    perform _send_sms(p_sender, v_reply, 'hi', 'inbound', null);
    return jsonb_build_object('reply', v_reply);
  end if;

  if v_body = 'PROFILE' then
    v_reply := 'LabourPass Jankari: ' || v_w.full_name || ' | ' || v_w.public_id || ' | Skills: ' ||
      coalesce((select string_agg(skill::text, ', ') from worker_skills where worker_id = v_w.id), '-') ||
      ' | Employers: ' || (select count(distinct employer_id) from engagements where worker_id = v_w.id) ||
      ' | Din(90d): ' || (select count(*) from attendance_records
        where worker_id = v_w.id and status in ('present','half_day') and attendance_date > current_date - 90);
  elsif v_body = 'WAGES' then
    v_reply := 'LabourPass Wages: ' || coalesce((select string_agg(to_char(payment_date,'DD-Mon')||' Rs.'||amount, ' | ')
      from (select payment_date, amount from wage_records where worker_id = v_w.id order by payment_date desc limit 3) x),
      'Koi record nahi');
  elsif v_body = 'PASSBOOK' then
    v_reply := 'LabourPass Passbook: Din ' ||
      (select count(*) from attendance_records where worker_id = v_w.id and status in ('present','half_day')) ||
      ' | Wages Rs.' || (select coalesce(sum(amount),0) from wage_records where worker_id = v_w.id) ||
      ' | Link: /verify/passbook/' || v_w.public_id;
  elsif v_body like 'WAGEDISPUTE%' then
    insert into disputes(worker_id, employer_id, dispute_type, description, reported_via)
      values (v_w.id, (select employer_id from wage_records where worker_id = v_w.id order by created_at desc limit 1),
              'wage', p_body, 'sms') returning id into v_disp;
    v_reply := 'LabourPass: Wage vivad ' || substr(v_disp::text,1,8) || ' register hua. 48 ghante mein jaanch hogi.';
  elsif v_body like 'DISPUTE%' then
    insert into disputes(worker_id, employer_id, dispute_type, description, reported_via)
      values (v_w.id, (select employer_id from attendance_records where worker_id = v_w.id order by created_at desc limit 1),
              'attendance', p_body, 'sms') returning id into v_disp;
    v_reply := 'LabourPass: Vivad ' || substr(v_disp::text,1,8) || ' register hua. 48 ghante mein jaanch hogi.';
  elsif v_body in ('1','2') then
    select * into v_tr from trust_ratings
      where worker_id = v_w.id and sms_sent_at is not null and responded_at is null
      order by sms_sent_at desc limit 1;
    if v_tr.id is null then
      v_reply := 'LabourPass: Koi pending rating nahi hai.';
    else
      update trust_ratings set rating = v_body::smallint, responded_at = now(), response_raw = v_body where id = v_tr.id;
      perform recompute_trust(v_tr.employer_id);
      v_reply := 'LabourPass: Shukriya! Aapka jawab darj hua.';
    end if;
  elsif v_body = 'HELP' then
    v_reply := 'LabourPass: PROFILE, WAGES, PASSBOOK, DISPUTE <date>, WAGEDISPUTE <amt>, 1/2 (rating) bhejein.';
  else
    v_reply := 'LabourPass: Samajh nahi aaya. HELP bhejein commands ke liye.';
  end if;

  perform _send_sms(p_sender, v_reply, v_w.preferred_language, 'inbound', null);
  return jsonb_build_object('reply', v_reply);
end; $$;

-- ============================================================
-- PUBLIC VERIFY (no auth; PII-safe)
-- ============================================================
create or replace function pub_passbook(p_public_id text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_w workers;
begin
  select * into v_w from workers where public_id = p_public_id;
  if v_w.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object(
    'found', true,
    'worker', jsonb_build_object('name', v_w.full_name, 'public_id', v_w.public_id,
       'state', v_w.state, 'district', v_w.district,
       'skills', coalesce((select jsonb_agg(skill::text) from worker_skills where worker_id = v_w.id), '[]'::jsonb)),
    'summary', jsonb_build_object(
       'days_worked', (select count(*) from attendance_records where worker_id = v_w.id and status in ('present','half_day')),
       'days_absent', (select count(*) from attendance_records where worker_id = v_w.id and status = 'absent'),
       'total_wages', (select coalesce(sum(amount),0) from wage_records where worker_id = v_w.id),
       'employers', (select count(distinct employer_id) from engagements where worker_id = v_w.id),
       'certificates', (select count(*) from experience_certificates where worker_id = v_w.id and not is_revoked)),
    'wages', coalesce((select jsonb_agg(row_to_json(t)) from (
       select payment_date, amount, payment_mode::text as mode,
              (select full_name from employers e where e.id = wage_records.employer_id) as employer
       from wage_records where worker_id = v_w.id order by payment_date desc limit 12) t), '[]'::jsonb),
    'employers', coalesce((select jsonb_agg(distinct e.full_name)
       from engagements g join employers e on e.id = g.employer_id where g.worker_id = v_w.id), '[]'::jsonb),
    'certificates', coalesce((select jsonb_agg(row_to_json(c)) from (
       select certificate_no, role_title, start_date, end_date from experience_certificates
       where worker_id = v_w.id and not is_revoked) c), '[]'::jsonb));
end; $$;

create or replace function pub_verify_certificate(p_cert_no text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare c experience_certificates;
begin
  select * into c from experience_certificates where certificate_no = p_cert_no;
  if c.id is null then return jsonb_build_object('found', false); end if;
  return jsonb_build_object('found', true, 'valid', not c.is_revoked,
    'certificate', jsonb_build_object(
      'certificate_no', c.certificate_no,
      'worker_name', (select full_name from workers where id = c.worker_id),
      'worker_public_id', (select public_id from workers where id = c.worker_id),
      'employer_name', (select full_name from employers where id = c.employer_id),
      'role', c.role_title, 'skills', c.skills_certified, 'worksite', c.worksite_name,
      'start_date', c.start_date, 'end_date', c.end_date, 'total_days', c.total_days,
      'conduct', c.conduct_remarks, 'issued_at', c.issued_at, 'is_revoked', c.is_revoked,
      'revoke_reason', c.revoke_reason));
end; $$;

-- ============================================================
-- ADMIN RPCs
-- ============================================================
create or replace function admin_dashboard(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return jsonb_build_object(
    'workers', (select count(*) from workers),
    'employers', (select count(*) from employers),
    'wages_total', (select coalesce(sum(amount),0) from wage_records),
    'certificates', (select count(*) from experience_certificates where not is_revoked),
    'pending_employers', (select count(*) from employers where status = 'pending'),
    'open_disputes', (select count(*) from disputes where status in ('open','investigating')),
    'low_trust', (select count(*) from employers where trust_score is not null and trust_score < 60));
end; $$;

create or replace function admin_list_employers(p_token text, p_status text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.created_at desc) from (
    select id, full_name, company_name, phone, state, district, status::text, trust_score, total_workers, created_at
    from employers where (p_status is null or status::text = p_status)) t), '[]'::jsonb);
end; $$;

create or replace function admin_approve_employer(p_token text, p_employer uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin uuid; v_emp employers;
begin
  v_admin := _admin_id(p_token);
  update employers set status = 'approved', approved_by = v_admin, approved_at = now()
    where id = p_employer returning * into v_emp;
  perform _send_sms(v_emp.phone, 'LabourPass: Aapka employer account approve ho gaya. Ab workers register kar sakte hain.', 'hi', 'employer', v_emp.id);
  return to_jsonb(v_emp);
end; $$;

create or replace function admin_suspend_employer(p_token text, p_employer uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp employers;
begin
  perform _admin_id(p_token);
  update employers set status = 'suspended' where id = p_employer returning * into v_emp;
  return to_jsonb(v_emp);
end; $$;

create or replace function admin_list_workers(p_token text, p_search text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select w.id, w.public_id, w.full_name, w.phone, w.state, w.district,
           (select count(distinct employer_id) from engagements e where e.worker_id = w.id) as employers,
           (select coalesce(sum(amount),0) from wage_records g where g.worker_id = w.id) as total_wages
    from workers w
    where (p_search is null or w.full_name ilike '%'||p_search||'%' or w.phone like '%'||p_search||'%' or w.public_id ilike '%'||p_search||'%')
    order by w.created_at desc limit 200) t), '[]'::jsonb);
end; $$;

create or replace function admin_list_disputes(p_token text, p_status text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.created_at desc) from (
    select d.id, d.dispute_type::text, d.status::text, d.description, d.created_at, d.resolution_notes,
           w.full_name as worker_name, w.public_id, w.phone,
           (select full_name from employers e where e.id = d.employer_id) as employer_name
    from disputes d join workers w on w.id = d.worker_id
    where (p_status is null or d.status::text = p_status)) t), '[]'::jsonb);
end; $$;

create or replace function admin_update_dispute(p_token text, p_dispute uuid, p_status text, p_notes text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin uuid; d disputes; v_w workers;
begin
  v_admin := _admin_id(p_token);
  update disputes set status = p_status::dispute_status, resolution_notes = coalesce(p_notes, resolution_notes),
    assigned_to = v_admin, resolved_at = case when p_status in ('resolved','rejected') then now() else resolved_at end,
    updated_at = now()
    where id = p_dispute returning * into d;
  if p_status = 'resolved' then
    select * into v_w from workers where id = d.worker_id;
    perform _send_sms(v_w.phone,
      'LabourPass: Aapka vivad '||substr(d.id::text,1,8)||' suljha diya gaya. '||coalesce(p_notes,''),
      v_w.preferred_language, 'dispute', d.id);
  end if;
  return to_jsonb(d);
end; $$;

create or replace function admin_sms_logs(p_token text, p_limit int default 100) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t)) from (
    select direction::text, phone, message, status::text, reference_type, created_at
    from sms_logs order by created_at desc limit p_limit) t), '[]'::jsonb);
end; $$;

create or replace function admin_trust_scores(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return coalesce((select jsonb_agg(row_to_json(t) order by t.trust_score asc nulls last) from (
    select id, full_name, company_name, trust_score,
           (select count(*) from trust_ratings tr where tr.employer_id = employers.id and responded_at is not null) as ratings
    from employers where trust_score is not null) t), '[]'::jsonb);
end; $$;

create or replace function admin_wage_analytics(p_token text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _admin_id(p_token);
  return jsonb_build_object(
    'by_state', coalesce((select jsonb_agg(row_to_json(t)) from (
      select coalesce(w.state,'Unknown') as state, sum(g.amount) as total, count(*) as payments
      from wage_records g join workers w on w.id = g.worker_id group by w.state order by sum(g.amount) desc) t), '[]'::jsonb),
    'by_skill', coalesce((select jsonb_agg(row_to_json(t)) from (
      select s.skill::text as skill, count(distinct s.worker_id) as workers
      from worker_skills s group by s.skill order by count(*) desc) t), '[]'::jsonb),
    'by_month', coalesce((select jsonb_agg(row_to_json(t)) from (
      select to_char(date_trunc('month', payment_date),'Mon YY') as month, sum(amount) as total
      from wage_records group by date_trunc('month', payment_date) order by date_trunc('month', payment_date)) t), '[]'::jsonb));
end; $$;

create or replace function admin_revoke_certificate(p_token text, p_cert uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare v_admin uuid; c experience_certificates;
begin
  v_admin := _admin_id(p_token);
  update experience_certificates set is_revoked = true, revoked_by = v_admin, revoked_at = now(), revoke_reason = p_reason
    where id = p_cert returning * into c;
  return to_jsonb(c);
end; $$;
