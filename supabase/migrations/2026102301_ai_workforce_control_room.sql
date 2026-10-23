-- Provider-neutral ProLine AI workforce control room.
-- The Stace pilot is created in setup_required state. Nothing in this migration
-- purchases a service, enables Grok billing, or removes the Paperclip fallback.

begin;

create table if not exists public.ai_agents (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  slug text not null,
  name text not null,
  title text not null,
  provider text not null default 'grok' check (provider in ('grok', 'paperclip', 'manual')),
  status text not null default 'planned' check (status in ('planned', 'setup_required', 'idle', 'running', 'paused', 'degraded', 'error')),
  active boolean not null default false,
  pilot boolean not null default false,
  colour text not null default '#64748b',
  accessory text not null default 'badge',
  instructions text not null default '',
  schedule_label text,
  current_work text,
  external_agent_id text,
  next_run_at timestamptz,
  last_checkin_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organisation_id, slug)
);

create table if not exists public.ai_agent_runs (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  provider_run_id text,
  trigger_type text not null default 'scheduled' check (trigger_type in ('scheduled', 'manual', 'webhook', 'comparison')),
  status text not null default 'running' check (status in ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled')),
  summary text,
  items jsonb not null default '[]'::jsonb,
  item_count integer not null default 0 check (item_count between 0 and 8),
  error text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) <= 8)
);

create unique index if not exists ai_agent_runs_provider_id_idx
  on public.ai_agent_runs (organisation_id, agent_id, provider_run_id)
  where provider_run_id is not null;
create index if not exists ai_agent_runs_recent_idx
  on public.ai_agent_runs (organisation_id, created_at desc);

create table if not exists public.ai_agent_commands (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  command_type text not null check (command_type in ('run_now', 'pause', 'resume')),
  status text not null default 'pending' check (status in ('pending', 'dispatching', 'accepted', 'succeeded', 'failed', 'cancelled')),
  payload jsonb not null default '{}'::jsonb,
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  dispatched_at timestamptz,
  completed_at timestamptz,
  result jsonb,
  error text
);

create index if not exists ai_agent_commands_recent_idx
  on public.ai_agent_commands (organisation_id, requested_at desc);

create table if not exists public.ai_action_proposals (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  category text not null check (category in ('customer_message', 'schedule', 'job_change', 'finance', 'purchase', 'delete', 'legal', 'complaint', 'other')),
  title text not null,
  summary text not null,
  risk_level text not null default 'medium' check (risk_level in ('low', 'medium', 'high', 'critical')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'expired', 'executed', 'failed')),
  source_refs jsonb not null default '[]'::jsonb,
  proposed_action jsonb not null default '{}'::jsonb,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  executed_at timestamptz,
  execution_result jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ai_action_proposals_pending_idx
  on public.ai_action_proposals (organisation_id, status, created_at desc);

create table if not exists public.integration_health (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  connector text not null,
  display_name text not null,
  provider text not null,
  status text not null default 'setup_required' check (status in ('setup_required', 'available', 'connected', 'degraded', 'error', 'disabled')),
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_error text,
  details jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (organisation_id, connector)
);

alter table public.general_tasks add column if not exists ai_source_agent_id uuid references public.ai_agents(id) on delete set null;
alter table public.general_tasks add column if not exists ai_dedupe_key text;
create unique index if not exists general_tasks_ai_dedupe_idx
  on public.general_tasks (organisation_id, ai_dedupe_key)
  where ai_dedupe_key is not null;

alter table public.ai_agents enable row level security;
alter table public.ai_agent_runs enable row level security;
alter table public.ai_agent_commands enable row level security;
alter table public.ai_action_proposals enable row level security;
alter table public.integration_health enable row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'ai_agents', 'ai_agent_runs', 'ai_agent_commands',
    'ai_action_proposals', 'integration_health'
  ] loop
    execute format('drop policy if exists ai_workforce_admin_select on public.%I', table_name);
    execute format(
      'create policy ai_workforce_admin_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin())',
      table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
  end loop;
end $$;

create or replace function private.seed_ai_workforce(target_organisation uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  insert into public.ai_agents (
    organisation_id, slug, name, title, provider, status, active, pilot,
    colour, accessory, instructions, schedule_label
  ) values
    (target_organisation, 'bruce', 'Bruce', 'Chief of Staff', 'grok', 'planned', false, false, '#1e3a8a', 'clipboard',
      'Prepare concise weekday morning and evening exception summaries. Coordinate the other roles. Never send, purchase, delete, change schedules, alter CRM records or make financial commitments without administrator approval.',
      'Weekdays 07:30 and 16:30'),
    (target_organisation, 'stace', 'Stace', 'Live Jobs Controller', 'grok', 'setup_required', true, true, '#f97316', 'calendar_headset',
      'Own live-job visibility and scheduling exceptions. Use current ProLine evidence only. Flag overdue jobs, missing assignments, unpaid deposits, schedule clashes and decisions. Return no more than eight short items or 300 words and ask one clear question when human input is needed. Never contact customers or change CRM records.',
      'Weekdays 07:00, then every 30 minutes until 18:00'),
    (target_organisation, 'rodney', 'Rodney', 'Growth Controller', 'grok', 'planned', false, false, '#16a34a', 'quote_sheet',
      'Own website and MyBuilder leads, quote follow-ups, reviews and referrals. Prepare drafts only. Never send a customer message or commit a price without approval.',
      '07:00–21:00, five-minute fallback'),
    (target_organisation, 'derrick', 'Derrick', 'Finance Controller', 'grok', 'planned', false, false, '#0f766e', 'ledger_pound',
      'Own deposits, balances, invoices, CIS and payroll exceptions, and cash collection. Reconcile evidence and prepare approval proposals. Never move money, issue refunds or alter financial records.',
      'Weekdays 09:00 and 15:00; Friday cash report'),
    (target_organisation, 'big-john', 'Big John', 'Site Readiness Controller', 'grok', 'planned', false, false, '#ca8a04', 'hard_hat_hammer',
      'Own materials, scaffolding, fleet, MOT, suppliers and next-day site readiness. Flag missing evidence and prepare internal tasks. Never place orders or commit supplier spend without approval.',
      'Weekdays 06:45 and 15:30')
  on conflict (organisation_id, slug) do nothing;

  insert into public.integration_health (organisation_id, connector, display_name, provider, status, details)
  values
    (target_organisation, 'proline_mcp', 'ProLine CRM', 'proline', 'available', '{"mode":"read_only"}'::jsonb),
    (target_organisation, 'grok_bot', 'Grok Bot', 'grok', 'setup_required', '{"billing_enabled":false}'::jsonb),
    (target_organisation, 'paperclip', 'Paperclip fallback', 'paperclip', 'available', '{"fallback":true}'::jsonb)
  on conflict (organisation_id, connector) do nothing;
end;
$$;

do $$
declare organisation_row record;
begin
  for organisation_row in select id from public.organisations loop
    perform private.seed_ai_workforce(organisation_row.id);
  end loop;
end $$;

create or replace function private.seed_ai_workforce_after_organisation()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  perform private.seed_ai_workforce(new.id);
  return new;
end;
$$;

drop trigger if exists seed_ai_workforce_on_organisation on public.organisations;
create trigger seed_ai_workforce_on_organisation
after insert on public.organisations
for each row execute function private.seed_ai_workforce_after_organisation();

create or replace function public.proline_agent_checkin(
  target_organisation uuid,
  agent_slug text,
  provider_run_id text,
  run_status text,
  run_summary text,
  run_items jsonb default '[]'::jsonb,
  run_trigger text default 'scheduled',
  next_run timestamptz default null,
  run_error text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  run_id uuid;
  safe_items jsonb := coalesce(run_items, '[]'::jsonb);
begin
  if run_status not in ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled') then
    raise exception 'invalid run status';
  end if;
  if run_trigger not in ('scheduled', 'manual', 'webhook', 'comparison') then
    raise exception 'invalid run trigger';
  end if;
  if jsonb_typeof(safe_items) <> 'array' or jsonb_array_length(safe_items) > 8 then
    raise exception 'a check-in may contain no more than eight items';
  end if;
  if length(coalesce(run_summary, '')) > 3000 then
    raise exception 'check-in summary is too long';
  end if;

  select * into target_agent from public.ai_agents
  where organisation_id = target_organisation and slug = agent_slug;
  if target_agent.id is null then raise exception 'agent not found'; end if;

  insert into public.ai_agent_runs (
    organisation_id, agent_id, provider_run_id, trigger_type, status,
    summary, items, item_count, error, finished_at
  ) values (
    target_organisation, target_agent.id, nullif(provider_run_id, ''), run_trigger, run_status,
    nullif(run_summary, ''), safe_items, jsonb_array_length(safe_items), nullif(run_error, ''),
    case when run_status in ('succeeded', 'partial', 'failed', 'cancelled') then now() else null end
  )
  on conflict (organisation_id, agent_id, provider_run_id) where provider_run_id is not null
  do update set
    status = excluded.status,
    summary = excluded.summary,
    items = excluded.items,
    item_count = excluded.item_count,
    error = excluded.error,
    finished_at = excluded.finished_at
  returning id into run_id;

  update public.ai_agents set
    status = case when run_status = 'running' then 'running' when run_status = 'failed' then 'error' else 'idle' end,
    current_work = case when run_status = 'running' then left(run_summary, 240) else null end,
    next_run_at = next_run,
    last_checkin_at = now(),
    last_success_at = case when run_status = 'succeeded' then now() else last_success_at end,
    last_error = case when run_status = 'failed' then left(run_error, 500) else null end,
    updated_at = now()
  where id = target_agent.id;

  return run_id;
end;
$$;

create or replace function public.proline_create_internal_task(
  target_organisation uuid,
  agent_slug text,
  dedupe_key text,
  task_title text,
  due_on date default null,
  task_priority text default 'medium',
  task_category text default 'AI agent',
  task_notes text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  agent_id uuid;
  task_id text;
begin
  if task_priority not in ('low', 'medium', 'high') then raise exception 'invalid priority'; end if;
  if length(trim(task_title)) < 1 or length(task_title) > 180 then raise exception 'invalid task title'; end if;
  if length(trim(dedupe_key)) < 1 or length(dedupe_key) > 180 then raise exception 'invalid dedupe key'; end if;
  select id into agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if agent_id is null then raise exception 'agent not found'; end if;

  select id into task_id from public.general_tasks
  where organisation_id = target_organisation and ai_dedupe_key = dedupe_key;
  if task_id is not null then return task_id; end if;

  task_id := gen_random_uuid()::text;
  insert into public.general_tasks (
    id, organisation_id, title, completed, due_date, priority, category,
    notes, created_at, assigned_to, ai_source_agent_id, ai_dedupe_key
  ) values (
    task_id, target_organisation, trim(task_title), false, due_on::text, task_priority,
    left(task_category, 80), left(task_notes, 2000), current_date::text, '[]'::jsonb,
    agent_id, trim(dedupe_key)
  );
  return task_id;
end;
$$;

create or replace function public.proline_update_internal_task(
  target_organisation uuid,
  agent_slug text,
  task_id text,
  mark_completed boolean default null,
  due_on date default null,
  task_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  agent_id uuid;
  changed integer;
begin
  select id into agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if agent_id is null then raise exception 'agent not found'; end if;
  update public.general_tasks set
    completed = coalesce(mark_completed, completed),
    completed_date = case when mark_completed is true then current_date::text when mark_completed is false then null else completed_date end,
    due_date = coalesce(due_on::text, due_date),
    notes = coalesce(left(task_notes, 2000), notes)
  where organisation_id = target_organisation and id = task_id and ai_source_agent_id = agent_id;
  get diagnostics changed = row_count;
  return changed = 1;
end;
$$;

create or replace function public.proline_submit_action_proposal(
  target_organisation uuid,
  agent_slug text,
  proposal_category text,
  proposal_title text,
  proposal_summary text,
  proposal_risk text default 'medium',
  proposal_sources jsonb default '[]'::jsonb,
  proposal_action jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  agent_id uuid;
  proposal_id uuid;
begin
  if proposal_category not in ('customer_message', 'schedule', 'job_change', 'finance', 'purchase', 'delete', 'legal', 'complaint', 'other') then raise exception 'invalid category'; end if;
  if proposal_risk not in ('low', 'medium', 'high', 'critical') then raise exception 'invalid risk'; end if;
  select id into agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if agent_id is null then raise exception 'agent not found'; end if;
  insert into public.ai_action_proposals (
    organisation_id, agent_id, category, title, summary, risk_level, source_refs, proposed_action
  ) values (
    target_organisation, agent_id, proposal_category, left(proposal_title, 180),
    left(proposal_summary, 2000), proposal_risk, coalesce(proposal_sources, '[]'::jsonb),
    coalesce(proposal_action, '{}'::jsonb)
  ) returning id into proposal_id;
  return proposal_id;
end;
$$;

revoke all on function private.seed_ai_workforce(uuid) from public, anon, authenticated;
revoke all on function public.proline_agent_checkin(uuid, text, text, text, text, jsonb, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) from public, anon, authenticated;
revoke all on function public.proline_submit_action_proposal(uuid, text, text, text, text, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.proline_agent_checkin(uuid, text, text, text, text, jsonb, text, timestamptz, text) to service_role;
grant execute on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) to service_role;
grant execute on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) to service_role;
grant execute on function public.proline_submit_action_proposal(uuid, text, text, text, text, text, jsonb, jsonb) to service_role;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'ai_agents', 'ai_agent_runs', 'ai_agent_commands',
    'ai_action_proposals', 'integration_health'
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
