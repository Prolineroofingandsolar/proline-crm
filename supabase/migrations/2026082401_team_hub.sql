-- ProLine CRM Team Hub: staff messages and shared day planning.
-- Apply only after 2026080902_enforce_rls.sql.
begin;

-- Keep this migration self-contained for projects whose auth foundation was
-- installed manually before migrations were tracked by the CLI.
create schema if not exists private;
revoke all on schema private from public;

create or replace function private.current_organisation_id()
returns uuid language sql stable security definer set search_path = public
as $$ select organisation_id from public.profiles where id = auth.uid() and active limit 1 $$;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role = 'admin' from public.profiles where id = auth.uid() and active), false) $$;

create or replace function private.current_worker_ids()
returns text[] language sql stable security definer set search_path = public
as $$ select array_remove(array[auth.uid()::text, legacy_user_id], null) from public.profiles where id = auth.uid() and active $$;

grant usage on schema private to authenticated;
grant execute on function private.current_organisation_id() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.current_worker_ids() to authenticated;

create table if not exists public.team_messages (
  id text primary key,
  organisation_id uuid not null default private.current_organisation_id(),
  author_id text not null,
  author_name text not null default '',
  body text not null check (char_length(trim(body)) between 1 and 4000),
  day text,
  lead_id text references public.leads(id) on delete set null,
  created_at text not null
);

create index if not exists team_messages_org_created_idx
  on public.team_messages (organisation_id, created_at desc);

create table if not exists public.team_day_plans (
  id text primary key,
  organisation_id uuid not null default private.current_organisation_id(),
  day text not null,
  title text not null check (char_length(trim(title)) between 1 and 200),
  notes text not null default '',
  start_time text,
  end_time text,
  lead_id text references public.leads(id) on delete set null,
  assigned_to jsonb not null default '[]'::jsonb,
  created_by text not null,
  created_at text not null
);

create index if not exists team_day_plans_org_day_idx
  on public.team_day_plans (organisation_id, day, start_time);

alter table public.team_messages enable row level security;
alter table public.team_day_plans enable row level security;

drop policy if exists team_messages_select on public.team_messages;
drop policy if exists team_messages_insert on public.team_messages;
drop policy if exists team_messages_delete on public.team_messages;
create policy team_messages_select on public.team_messages for select to authenticated
  using (organisation_id = private.current_organisation_id());
create policy team_messages_insert on public.team_messages for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and author_id = any(private.current_worker_ids()));
create policy team_messages_delete on public.team_messages for delete to authenticated
  using (organisation_id = private.current_organisation_id() and (author_id = any(private.current_worker_ids()) or private.is_admin()));

drop policy if exists team_day_plans_select on public.team_day_plans;
drop policy if exists team_day_plans_insert on public.team_day_plans;
drop policy if exists team_day_plans_update on public.team_day_plans;
drop policy if exists team_day_plans_delete on public.team_day_plans;
create policy team_day_plans_select on public.team_day_plans for select to authenticated
  using (organisation_id = private.current_organisation_id());
create policy team_day_plans_insert on public.team_day_plans for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and created_by = any(private.current_worker_ids()));
create policy team_day_plans_update on public.team_day_plans for update to authenticated
  using (organisation_id = private.current_organisation_id())
  with check (organisation_id = private.current_organisation_id());
create policy team_day_plans_delete on public.team_day_plans for delete to authenticated
  using (organisation_id = private.current_organisation_id());

revoke all on public.team_messages, public.team_day_plans from anon;
grant select, insert, delete on public.team_messages to authenticated;
grant select, insert, update, delete on public.team_day_plans to authenticated;

commit;
