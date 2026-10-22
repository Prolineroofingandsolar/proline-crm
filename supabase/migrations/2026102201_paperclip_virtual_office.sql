-- ProLine Virtual Office: secure, organisation-scoped Paperclip mirror and command queue.
-- Paperclip remains private on the office machine. A local bridge writes only the
-- minimum agent/task state needed by the CRM and polls this queue for approved commands.
begin;

create table if not exists public.paperclip_connection_status (
  organisation_id uuid primary key references public.organisations(id) on delete cascade,
  paperclip_company_id text not null,
  bridge_instance text,
  connected boolean not null default false,
  last_seen_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  synced_at timestamptz not null default now()
);

create table if not exists public.paperclip_agents (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  paperclip_agent_id text not null,
  name text not null,
  shortname text,
  title text,
  role text,
  status text not null default 'idle',
  adapter_type text,
  heartbeat_enabled boolean not null default false,
  heartbeat_interval_seconds integer,
  last_run_at timestamptz,
  synced_at timestamptz not null default now(),
  primary key (organisation_id, paperclip_agent_id)
);

create table if not exists public.paperclip_issues (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  paperclip_issue_id text not null,
  identifier text,
  title text not null,
  status text not null,
  priority text,
  assignee_agent_id text,
  project_id text,
  created_at timestamptz,
  updated_at timestamptz,
  synced_at timestamptz not null default now(),
  primary key (organisation_id, paperclip_issue_id)
);

create table if not exists public.paperclip_approvals (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  paperclip_approval_id text not null,
  approval_type text,
  status text not null,
  requested_by_agent_id text,
  issue_id text,
  created_at timestamptz,
  resolved_at timestamptz,
  synced_at timestamptz not null default now(),
  primary key (organisation_id, paperclip_approval_id)
);

create table if not exists public.paperclip_activity (
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  paperclip_activity_id text not null,
  action text not null,
  actor_agent_id text,
  actor_name text,
  issue_identifier text,
  issue_title text,
  created_at timestamptz not null,
  synced_at timestamptz not null default now(),
  primary key (organisation_id, paperclip_activity_id)
);

create table if not exists public.paperclip_commands (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  requested_by uuid not null default auth.uid() references auth.users(id),
  command_type text not null check (command_type in ('wake_agent', 'pause_agent', 'resume_agent')),
  paperclip_agent_id text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'processing', 'succeeded', 'failed')),
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  completed_at timestamptz,
  result jsonb,
  error text
);

create index if not exists paperclip_issues_assignee_idx
  on public.paperclip_issues (organisation_id, assignee_agent_id, status);
create index if not exists paperclip_activity_created_idx
  on public.paperclip_activity (organisation_id, created_at desc);
create index if not exists paperclip_commands_pending_idx
  on public.paperclip_commands (organisation_id, status, created_at);

alter table public.paperclip_connection_status enable row level security;
alter table public.paperclip_agents enable row level security;
alter table public.paperclip_issues enable row level security;
alter table public.paperclip_approvals enable row level security;
alter table public.paperclip_activity enable row level security;
alter table public.paperclip_commands enable row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'paperclip_connection_status', 'paperclip_agents', 'paperclip_issues',
    'paperclip_approvals', 'paperclip_activity'
  ] loop
    execute format('drop policy if exists paperclip_admin_select on public.%I', table_name);
    execute format(
      'create policy paperclip_admin_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin())',
      table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
  end loop;
end $$;

drop policy if exists paperclip_command_select on public.paperclip_commands;
drop policy if exists paperclip_command_insert on public.paperclip_commands;
create policy paperclip_command_select on public.paperclip_commands for select to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());
create policy paperclip_command_insert on public.paperclip_commands for insert to authenticated
  with check (
    organisation_id = private.current_organisation_id()
    and requested_by = auth.uid()
    and private.is_admin()
    and status = 'pending'
  );
revoke all on public.paperclip_commands from anon, authenticated;
grant select, insert (command_type, paperclip_agent_id, payload) on public.paperclip_commands to authenticated;

create or replace function public.claim_paperclip_commands(target_organisation uuid, command_limit integer default 20)
returns setof public.paperclip_commands
language plpgsql
security definer
set search_path = public, private
as $$
begin
  return query
  with candidates as (
    select id
    from public.paperclip_commands
    where organisation_id = target_organisation and status = 'pending'
    order by created_at
    for update skip locked
    limit greatest(1, least(command_limit, 50))
  )
  update public.paperclip_commands command
     set status = 'processing', claimed_at = now()
    from candidates
   where command.id = candidates.id
  returning command.*;
end;
$$;

revoke all on function public.claim_paperclip_commands(uuid, integer) from public, anon, authenticated;
grant execute on function public.claim_paperclip_commands(uuid, integer) to service_role;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'paperclip_connection_status', 'paperclip_agents', 'paperclip_issues',
    'paperclip_approvals', 'paperclip_activity', 'paperclip_commands'
  ] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;

commit;
