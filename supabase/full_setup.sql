-- LabourPass full DB setup (idempotent; safe to re-run in Supabase SQL editor)


-- ===== 0001_init.sql =====
-- ============================================================
-- LabourPass â€” Schema (adapted from blueprint Â§11 for Supabase)
-- Backend is pure Postgres: SECURITY DEFINER RPCs + custom token
-- sessions + hash-chain triggers. No Edge Functions required.
-- ============================================================

create extension if not exists pgcrypto;   -- digest, gen_random_bytes, crypt, gen_salt
create extension if not exists pg_trgm;     -- fuzzy worker name search

-- ------------------------------------------------------------
-- ENUMS
-- ------------------------------------------------------------
do $$ begin
  create type worker_skill as enum (
    'mason','plumber','electrician','painter','carpenter','welder','helper',
    'domestic_worker','agricultural_labourer','driver','security_guard','cleaner','cook','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type attendance_status as enum ('present','absent','half_day','paid_leave');
exception when duplicate_object then null; end $$;

do $$ begin
  create type payment_mode as enum ('cash','upi','bank_transfer','cheque');
exception when duplicate_object then null; end $$;

do $$ begin
  create type dispute_status as enum ('open','investigating','resolved','rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type dispute_type as enum ('attendance','wage','certificate','other');
exception when duplicate_object then null; end $$;

do $$ begin
  create type sms_direction as enum ('outbound','inbound');
exception when duplicate_object then null; end $$;

do $$ begin
  create type sms_status as enum ('queued','sent','delivered','failed','received');
exception when duplicate_object then null; end $$;

do $$ begin
  create type employer_status as enum ('pending','approved','suspended','rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type language_code as enum ('hi','kn','ta','te','bn','mr','gu','or','en');
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------
-- CORE
-- ------------------------------------------------------------
create table if not exists admin_users (
  id            uuid primary key default gen_random_uuid(),
  email         varchar(255) unique not null,
  password_hash text not null,                  -- bcrypt via extensions.crypt
  full_name     varchar(150) not null,
  is_active     boolean default true,
  last_login_at timestamptz,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

create table if not exists employers (
  id            uuid primary key default gen_random_uuid(),
  phone         varchar(15) unique not null,
  full_name     varchar(150) not null,
  company_name  varchar(255),
  business_type varchar(100),
  address       text,
  district      varchar(100),
  state         varchar(100),
  pincode       varchar(10),
  status        employer_status default 'pending',
  trust_score   numeric(5,2),                   -- cached, recomputed by recompute_trust()
  total_workers int default 0,
  approved_by   uuid references admin_users(id),
  approved_at   timestamptz,
  deleted_at    timestamptz,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
create index if not exists idx_employers_phone  on employers(phone);
create index if not exists idx_employers_status on employers(status);
create index if not exists idx_employers_state  on employers(state);

create table if not exists workers (
  id            uuid primary key default gen_random_uuid(),
  public_id     varchar(16) unique not null default ('LP-' || upper(substr(encode(extensions.gen_random_bytes(4),'hex'),1,6))),
  phone         varchar(15) unique not null,
  full_name     varchar(150) not null,
  father_name   varchar(150),
  date_of_birth date,
  gender        varchar(20),
  aadhaar_last4 varchar(4),                      -- last 4 only (PII minimisation)
  address       text,
  district      varchar(100),
  state         varchar(100),
  pincode       varchar(10),
  preferred_language language_code default 'hi',
  photo_url     varchar(500),
  is_verified   boolean default false,
  is_active     boolean default true,
  registered_by uuid references employers(id),
  deleted_at    timestamptz,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);
create index if not exists idx_workers_phone     on workers(phone);
create index if not exists idx_workers_public_id on workers(public_id);
create index if not exists idx_workers_name_trgm on workers using gin (full_name gin_trgm_ops);
create index if not exists idx_workers_state     on workers(state);

create table if not exists worker_skills (
  id         uuid primary key default gen_random_uuid(),
  worker_id  uuid not null references workers(id) on delete cascade,
  skill      worker_skill not null,
  years_exp  smallint default 0,
  added_by   uuid references employers(id),
  created_at timestamptz default now(),
  unique (worker_id, skill)
);
create index if not exists idx_worker_skills_worker on worker_skills(worker_id);
create index if not exists idx_worker_skills_skill  on worker_skills(skill);

create table if not exists worksites (
  id           uuid primary key default gen_random_uuid(),
  employer_id  uuid not null references employers(id),
  name         varchar(255) not null,
  address      text,
  district     varchar(100),
  state        varchar(100),
  project_type varchar(100),
  start_date   date,
  end_date     date,
  is_active    boolean default true,
  created_at   timestamptz default now()
);
create index if not exists idx_worksites_employer on worksites(employer_id);

create table if not exists engagements (
  id          uuid primary key default gen_random_uuid(),
  employer_id uuid not null references employers(id),
  worker_id   uuid not null references workers(id),
  worksite_id uuid references worksites(id),
  start_date  date not null default current_date,
  end_date    date,
  daily_wage  numeric(10,2),
  role_title  varchar(100),
  is_active   boolean default true,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (employer_id, worker_id, worksite_id)
);
create index if not exists idx_engagements_employer on engagements(employer_id);
create index if not exists idx_engagements_worker   on engagements(worker_id);
create index if not exists idx_engagements_active   on engagements(is_active);

-- ------------------------------------------------------------
-- TRANSACTIONAL (hash-chained)
-- ------------------------------------------------------------
create table if not exists attendance_records (
  id              uuid primary key default gen_random_uuid(),
  chain_seq       bigserial,
  engagement_id   uuid not null references engagements(id),
  employer_id     uuid not null references employers(id),
  worker_id       uuid not null references workers(id),
  worksite_id     uuid references worksites(id),
  attendance_date date not null,
  status          attendance_status not null default 'present',
  marked_by       uuid references employers(id),
  prev_hash       text,
  record_hash     text,
  sms_sent        boolean default false,
  notes           text,
  created_at      timestamptz default now(),
  unique (engagement_id, attendance_date)
);
create index if not exists idx_attendance_worker      on attendance_records(worker_id);
create index if not exists idx_attendance_employer    on attendance_records(employer_id);
create index if not exists idx_attendance_date        on attendance_records(attendance_date);
create index if not exists idx_attendance_worker_date on attendance_records(worker_id, attendance_date);

create table if not exists wage_records (
  id              uuid primary key default gen_random_uuid(),
  chain_seq       bigserial,
  engagement_id   uuid not null references engagements(id),
  employer_id     uuid not null references employers(id),
  worker_id       uuid not null references workers(id),
  payment_date    date not null,
  amount          numeric(10,2) not null,
  payment_mode    payment_mode not null default 'cash',
  period_from     date,
  period_to       date,
  days_covered    smallint,
  reference_no    varchar(100),
  notes           text,
  prev_hash       text,
  record_hash     text,
  sms_sent        boolean default false,
  trust_sms_sent  boolean default false,
  idempotency_key varchar(100) unique,
  created_at      timestamptz default now()
);
create index if not exists idx_wages_worker       on wage_records(worker_id);
create index if not exists idx_wages_employer     on wage_records(employer_id);
create index if not exists idx_wages_payment_date on wage_records(payment_date);

create table if not exists experience_certificates (
  id               uuid primary key default gen_random_uuid(),
  certificate_no   varchar(30) unique not null,
  engagement_id    uuid references engagements(id),
  employer_id      uuid not null references employers(id),
  worker_id        uuid not null references workers(id),
  role_title       varchar(100),
  skills_certified text[],
  worksite_name    varchar(255),
  start_date       date not null,
  end_date         date not null,
  total_days       smallint,
  conduct_remarks  text,
  issued_by        varchar(150),
  issued_at        timestamptz default now(),
  is_revoked       boolean default false,
  revoked_by       uuid references admin_users(id),
  revoked_at       timestamptz,
  revoke_reason    text
);
create index if not exists idx_certs_worker   on experience_certificates(worker_id);
create index if not exists idx_certs_employer on experience_certificates(employer_id);

-- ------------------------------------------------------------
-- ENGAGEMENT / OVERSIGHT
-- ------------------------------------------------------------
create table if not exists trust_ratings (
  id             uuid primary key default gen_random_uuid(),
  wage_record_id uuid not null references wage_records(id),
  employer_id    uuid not null references employers(id),
  worker_id      uuid not null references workers(id),
  rating         smallint check (rating in (1,2)),    -- 1=paid in full, 2=not/partial
  sms_sent_at    timestamptz,
  responded_at   timestamptz,
  response_raw   varchar(10),
  is_valid       boolean default true,
  created_at     timestamptz default now(),
  unique (wage_record_id, worker_id)
);
create index if not exists idx_trust_employer  on trust_ratings(employer_id);
create index if not exists idx_trust_worker     on trust_ratings(worker_id);
create index if not exists idx_trust_responded  on trust_ratings(responded_at);

create table if not exists disputes (
  id               uuid primary key default gen_random_uuid(),
  worker_id        uuid not null references workers(id),
  employer_id      uuid references employers(id),
  dispute_type     dispute_type not null,
  reference_id     uuid,
  description      text,
  reported_via     varchar(20) default 'sms',
  status           dispute_status default 'open',
  assigned_to      uuid references admin_users(id),
  resolution_notes text,
  resolved_at      timestamptz,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);
create index if not exists idx_disputes_worker   on disputes(worker_id);
create index if not exists idx_disputes_status   on disputes(status);
create index if not exists idx_disputes_employer on disputes(employer_id);

-- ------------------------------------------------------------
-- INFRASTRUCTURE
-- ------------------------------------------------------------
create table if not exists sms_logs (
  id             uuid primary key default gen_random_uuid(),
  direction      sms_direction not null,
  phone          varchar(15) not null,
  message        text not null,
  language       language_code default 'hi',
  gateway        varchar(50) default 'simulated',
  status         sms_status default 'sent',
  delivered_at   timestamptz,
  error_message  text,
  retry_count    smallint default 0,
  reference_type varchar(50),
  reference_id   uuid,
  created_at     timestamptz default now()
);
create index if not exists idx_sms_phone     on sms_logs(phone);
create index if not exists idx_sms_status    on sms_logs(status);
create index if not exists idx_sms_created    on sms_logs(created_at);
create index if not exists idx_sms_reference on sms_logs(reference_type, reference_id);

create table if not exists otp_requests (
  id            uuid primary key default gen_random_uuid(),
  phone         varchar(15) not null,
  otp_hash      varchar(64) not null,
  expires_at    timestamptz not null,
  is_used       boolean default false,
  attempt_count smallint default 0,
  created_at    timestamptz default now()
);
create index if not exists idx_otp_phone on otp_requests(phone);

create table if not exists notifications (
  id             uuid primary key default gen_random_uuid(),
  recipient_id   uuid not null,
  recipient_type varchar(20) not null,   -- employer | admin
  title          varchar(255),
  body           text,
  is_read        boolean default false,
  link           varchar(500),
  created_at     timestamptz default now()
);
create index if not exists idx_notifs_recipient on notifications(recipient_id, is_read);

create table if not exists audit_logs (
  id         uuid primary key default gen_random_uuid(),
  actor_id   uuid,
  actor_type varchar(20),
  action     varchar(100) not null,
  table_name varchar(100),
  record_id  uuid,
  new_values jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_audit_actor   on audit_logs(actor_id);
create index if not exists idx_audit_created on audit_logs(created_at);

-- Custom token sessions (replaces blueprint refresh_tokens + Supabase Auth)
create table if not exists sessions (
  id         uuid primary key default gen_random_uuid(),
  token_hash text unique not null,        -- sha256(raw token)
  actor_type varchar(20) not null,        -- employer | admin
  actor_id   uuid not null,
  expires_at timestamptz not null,
  created_at timestamptz default now()
);
create index if not exists idx_sessions_actor on sessions(actor_type, actor_id);

-- ============================================================
-- HASH-CHAIN â€” tamper evidence on attendance + wage records
-- record_hash = sha256(canonical_fields || prev_hash); genesis prev='0'
-- ============================================================
create or replace function compute_record_hash() returns trigger as $$
declare
  v_prev text;
  v_canonical text;
begin
  if tg_table_name = 'attendance_records' then
    select record_hash into v_prev from attendance_records
      where worker_id = new.worker_id and chain_seq < new.chain_seq
      order by chain_seq desc limit 1;
    v_canonical := concat_ws('|', new.worker_id::text, new.employer_id::text,
                             new.attendance_date::text, new.status::text);
  elsif tg_table_name = 'wage_records' then
    select record_hash into v_prev from wage_records
      where worker_id = new.worker_id and chain_seq < new.chain_seq
      order by chain_seq desc limit 1;
    v_canonical := concat_ws('|', new.worker_id::text, new.employer_id::text,
                             new.payment_date::text, new.amount::text, new.payment_mode::text);
  end if;
  v_prev := coalesce(v_prev, '0');
  new.prev_hash := v_prev;
  new.record_hash := encode(extensions.digest(v_canonical || '|' || v_prev, 'sha256'), 'hex');
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_hash_attendance on attendance_records;
create trigger trg_hash_attendance before insert on attendance_records
  for each row execute function compute_record_hash();

drop trigger if exists trg_hash_wage on wage_records;
create trigger trg_hash_wage before insert on wage_records
  for each row execute function compute_record_hash();

-- Recompute a worker's chains and report first broken link (public-safe).
create or replace function public_verify_chain(p_public_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_worker uuid;
  rec record;
  v_prev text;
  v_calc text;
  v_canonical text;
  w_total int := 0; w_broken int := null;
  a_total int := 0; a_broken int := null;
begin
  select id into v_worker from workers where public_id = p_public_id;
  if v_worker is null then return jsonb_build_object('found', false); end if;

  -- wage chain
  v_prev := '0';
  for rec in select * from wage_records where worker_id = v_worker order by chain_seq asc loop
    w_total := w_total + 1;
    v_canonical := concat_ws('|', rec.worker_id::text, rec.employer_id::text,
                             rec.payment_date::text, rec.amount::text, rec.payment_mode::text);
    v_calc := encode(extensions.digest(v_canonical || '|' || v_prev, 'sha256'), 'hex');
    if w_broken is null and (rec.prev_hash <> v_prev or rec.record_hash <> v_calc) then
      w_broken := w_total;
    end if;
    v_prev := rec.record_hash;  -- continue from stored to localise the first break
  end loop;

  -- attendance chain
  v_prev := '0';
  for rec in select * from attendance_records where worker_id = v_worker order by chain_seq asc loop
    a_total := a_total + 1;
    v_canonical := concat_ws('|', rec.worker_id::text, rec.employer_id::text,
                             rec.attendance_date::text, rec.status::text);
    v_calc := encode(extensions.digest(v_canonical || '|' || v_prev, 'sha256'), 'hex');
    if a_broken is null and (rec.prev_hash <> v_prev or rec.record_hash <> v_calc) then
      a_broken := a_total;
    end if;
    v_prev := rec.record_hash;
  end loop;

  return jsonb_build_object(
    'found', true,
    'public_id', p_public_id,
    'wage', jsonb_build_object('total', w_total, 'intact', w_broken is null, 'broken_at', w_broken),
    'attendance', jsonb_build_object('total', a_total, 'intact', a_broken is null, 'broken_at', a_broken)
  );
end;
$$;

grant execute on function public_verify_chain(text) to anon, authenticated;


-- ===== 0002_auth_employer.sql =====
-- ============================================================
-- Sessions, auth, SMS helper, employer-facing RPCs
-- All RPCs are SECURITY DEFINER and validate a custom session
-- token internally; the anon role can call them but cannot touch
-- tables directly (RLS locks everything â€” see 0004).
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


-- ===== 0003_public_admin.sql =====
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


-- ===== 0004_rls_grants.sql =====
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
  -- publication doesn't exist (non-Supabase Postgres) â€” safe to ignore
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


-- ===== 0005_seed.sql =====
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


-- ===== 0006_extras.sql =====
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

