-- ============================================================
-- LabourPass — Schema (adapted from blueprint §11 for Supabase)
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
-- HASH-CHAIN — tamper evidence on attendance + wage records
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
