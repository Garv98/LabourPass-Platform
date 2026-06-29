-- ============================================================
-- Web Push subscriptions (Phase 2). Complement to SMS for
-- smartphone users. Run this file alone in the SQL editor.
-- ============================================================

create table if not exists push_subscriptions (
  id           uuid primary key default gen_random_uuid(),
  actor_type   varchar(20) not null,            -- 'employer' | 'worker'
  actor_id     uuid not null,                   -- employers.id or workers.id
  endpoint     text unique not null,            -- dedupe per browser/device
  subscription jsonb not null,
  created_at   timestamptz default now()
);
alter table push_subscriptions enable row level security;  -- only RPCs / service role touch it
create index if not exists idx_push_actor on push_subscriptions(actor_type, actor_id);

-- Employer saves own subscription (token-validated).
create or replace function emp_save_push(p_token text, p_sub jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_emp uuid;
begin
  v_emp := _employer_id(p_token);
  insert into push_subscriptions(actor_type, actor_id, endpoint, subscription)
  values ('employer', v_emp, p_sub->>'endpoint', p_sub)
  on conflict (endpoint) do update set subscription = excluded.subscription, actor_id = excluded.actor_id;
end; $$;

-- Worker saves subscription by public passbook id (demo-grade; in prod tie to a verified session).
create or replace function pub_save_push(p_public_id text, p_sub jsonb) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_worker uuid;
begin
  select id into v_worker from workers where public_id = p_public_id;
  if v_worker is null then raise exception 'NOT_FOUND'; end if;
  insert into push_subscriptions(actor_type, actor_id, endpoint, subscription)
  values ('worker', v_worker, p_sub->>'endpoint', p_sub)
  on conflict (endpoint) do update set subscription = excluded.subscription, actor_id = excluded.actor_id;
end; $$;

grant execute on function public.emp_save_push(text, jsonb) to anon, authenticated;
grant execute on function public.pub_save_push(text, jsonb) to anon, authenticated;
