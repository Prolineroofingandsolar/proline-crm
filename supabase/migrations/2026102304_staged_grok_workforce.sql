-- Staged, provider-neutral Grok workforce controls for the native ProLine CRM.
-- No subscription, paid usage, customer message, schedule change, payment or
-- purchase is created by this migration.

begin;

create table if not exists public.ai_workforce_settings (
  organisation_id uuid primary key references public.organisations(id) on delete cascade,
  target_plan text not null default 'premium' check (target_plan in ('premium', 'super', 'ultra', 'existing')),
  auto_topup_enabled boolean not null default false,
  weekly_usage_percent numeric(5,2) check (weekly_usage_percent between 0 and 100),
  usage_measured_at timestamptz,
  usage_week_resets_at timestamptz,
  usage_note text,
  max_report_items integer not null default 8 check (max_report_items between 1 and 8),
  max_report_words integer not null default 300 check (max_report_words between 50 and 300),
  paperclip_fallback_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_agent_acceptance (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  activation_order smallint not null check (activation_order between 1 and 5),
  gate_status text not null default 'locked' check (gate_status in ('locked', 'ready', 'pilot', 'passed', 'failed')),
  trial_started_at timestamptz,
  trial_passed_at timestamptz,
  remote_run_confirmed boolean not null default false,
  correct_organisation_confirmed boolean not null default false,
  duplicate_free_confirmed boolean not null default false,
  approval_boundaries_confirmed boolean not null default false,
  concise_reports_confirmed boolean not null default false,
  approved_by uuid references auth.users(id) on delete set null,
  approval_note text,
  updated_at timestamptz not null default now(),
  unique (organisation_id, agent_id),
  unique (organisation_id, activation_order)
);

create table if not exists public.ai_verified_lead_events (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  source text not null check (source in ('website', 'mybuilder_shortlisted')),
  source_event_id text not null,
  lead_id text not null references public.leads(id) on delete cascade,
  evidence text not null,
  created_at timestamptz not null default now(),
  unique (organisation_id, source, source_event_id)
);

alter table public.ai_workforce_settings enable row level security;
alter table public.ai_agent_acceptance enable row level security;
alter table public.ai_verified_lead_events enable row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array['ai_workforce_settings', 'ai_agent_acceptance', 'ai_verified_lead_events'] loop
    execute format('drop policy if exists ai_workforce_admin_select on public.%I', table_name);
    execute format(
      'create policy ai_workforce_admin_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin())',
      table_name
    );
    execute format('revoke all on public.%I from public, anon, authenticated', table_name);
    execute format('grant select on public.%I to authenticated', table_name);
  end loop;
end $$;

create or replace function private.seed_staged_ai_workforce(target_organisation uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  insert into public.ai_workforce_settings (organisation_id)
  values (target_organisation)
  on conflict (organisation_id) do nothing;

  update public.ai_agents set
    metadata = coalesce(metadata, '{}'::jsonb) || case slug
      when 'stace' then '{"activation_order":1,"reports_to":"bruce","required_connectors":["proline_mcp","grok_bot"],"alert_policy":"exceptions_only","max_items":8,"max_words":300}'::jsonb
      when 'bruce' then '{"activation_order":2,"reports_to":"will","required_connectors":["proline_mcp","grok_bot"],"alert_policy":"urgent_and_new_leads","max_items":8,"max_words":300}'::jsonb
      when 'rodney' then '{"activation_order":3,"reports_to":"bruce","required_connectors":["proline_mcp","grok_bot","gmail","mybuilder_email"],"mybuilder_requires_shortlist":true,"max_items":8,"max_words":300}'::jsonb
      when 'derrick' then '{"activation_order":4,"reports_to":"bruce","required_connectors":["proline_mcp","grok_bot","monzo_read_only"],"max_items":8,"max_words":300}'::jsonb
      when 'big-john' then '{"activation_order":5,"reports_to":"bruce","required_connectors":["proline_mcp","grok_bot","weather","mot"],"materials_mode":"suggestions_only","max_items":8,"max_words":300}'::jsonb
      else '{}'::jsonb end,
    instructions = case slug
      when 'bruce' then 'Act as Will''s Chief of Staff. Coordinate the specialist bots and report genuine new leads and urgent safety, complaint, same-day schedule, blocked-job, deposit, cash or vehicle risks immediately. Give concise 07:30 and 16:30 summaries. Never contact customers, commit spending, delete records, move money or change live schedules, owners, dates or stages without approval inside ProLine.'
      when 'stace' then 'Own weekday live jobs, scheduling exceptions, evidence-backed internal notes and task completion. Check for material CRM changes before a full review. Flag overdue work, missing assignments, unpaid deposits, clashes and decisions. Maximum eight items or 300 words. Never contact customers or change stages, owners, dates, schedules or finances without approval inside ProLine.'
      when 'rodney' then 'Own daily website, Gmail and MyBuilder leads, quote follow-ups at 3, 7 and 14 days, reviews and referrals. Alert Will immediately for genuine new leads. Never express interest on MyBuilder, incur a fee or create a MyBuilder customer lead before official shortlisting. Prepare customer drafts for approval and never send or commit a price automatically.'
      when 'derrick' then 'Own deposits before job start, completed-job balances, read-only Monzo matching, payroll and CIS exceptions. Create internal tasks and approval proposals only. Never move money, issue refunds, approve payroll or alter financial records automatically.'
      when 'big-john' then 'Own next-day materials, scaffolding, weather, fleet and MOT readiness. Suggest materials only when supported by job scope, measurements, photographs or worker updates; label estimates and ask when dimensions are missing. Never select suppliers, prepare baskets, place orders or commit spend.'
      else instructions end,
    schedule_label = case slug
      when 'stace' then 'Weekdays 07:00, then every 30 minutes until 18:00'
      when 'bruce' then 'Weekdays 07:30 and 16:30'
      when 'rodney' then '07:00–21:00, five-minute fallback'
      when 'derrick' then 'Weekdays 09:00 and 15:00; Friday cash report'
      when 'big-john' then 'Weekdays 06:45 and 15:30'
      else schedule_label end,
    updated_at = now()
  where organisation_id = target_organisation and slug in ('stace', 'bruce', 'rodney', 'derrick', 'big-john');

  insert into public.ai_agent_acceptance (organisation_id, agent_id, activation_order, gate_status, trial_started_at)
  select target_organisation, id,
    (metadata->>'activation_order')::smallint,
    case when slug = 'stace' then 'pilot' else 'locked' end,
    case when slug = 'stace' then now() else null end
  from public.ai_agents
  where organisation_id = target_organisation and slug in ('stace', 'bruce', 'rodney', 'derrick', 'big-john')
  on conflict (organisation_id, agent_id) do update set activation_order = excluded.activation_order;

  insert into public.integration_health (organisation_id, connector, display_name, provider, status, details)
  values
    (target_organisation, 'gmail', 'Gmail', 'google', 'setup_required', '{"mode":"read_and_draft","send_requires_approval":true}'::jsonb),
    (target_organisation, 'mybuilder_email', 'MyBuilder via Gmail', 'mybuilder', 'setup_required', '{"direct_login":false,"create_after_shortlist":true,"interest_requires_approval":true}'::jsonb),
    (target_organisation, 'monzo_read_only', 'Monzo read-only', 'monzo', 'setup_required', '{"mode":"read_only"}'::jsonb),
    (target_organisation, 'weather', 'Weather', 'proline', 'available', '{"mode":"read_only"}'::jsonb),
    (target_organisation, 'mot', 'MOT', 'dvsa', 'available', '{"mode":"read_only"}'::jsonb)
  on conflict (organisation_id, connector) do nothing;

  update public.integration_health set
    details = coalesce(details, '{}'::jsonb) || '{"mode":"controlled_internal_actions","customer_contact_requires_approval":true,"schedule_changes_require_approval":true,"financial_changes_require_approval":true}'::jsonb,
    updated_at = now()
  where organisation_id = target_organisation and connector = 'proline_mcp';
end;
$$;

do $$
declare organisation_row record;
begin
  for organisation_row in select id from public.organisations loop
    perform private.seed_staged_ai_workforce(organisation_row.id);
  end loop;
end $$;

create or replace function private.seed_staged_ai_workforce_after_organisation()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  perform private.seed_staged_ai_workforce(new.id);
  return new;
end;
$$;

drop trigger if exists seed_staged_ai_workforce_on_organisation on public.organisations;
create trigger seed_staged_ai_workforce_on_organisation
after insert on public.organisations
for each row execute function private.seed_staged_ai_workforce_after_organisation();

create or replace function public.proline_workforce_change_check(
  target_organisation uuid,
  agent_slug text,
  workflow_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  current_fingerprint text;
  previous_fingerprint text;
  snapshot jsonb;
begin
  if length(trim(coalesce(workflow_name, ''))) < 1 or length(workflow_name) > 80 then raise exception 'invalid workflow'; end if;
  select * into target_agent from public.ai_agents
  where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active agent not found'; end if;

  if agent_slug = 'rodney' then
    select jsonb_build_object(
      'leads', coalesce(jsonb_agg(jsonb_build_object('id', id, 'stage', stage, 'source', source, 'updated_at', updated_at) order by id)
        filter (where stage in ('New Lead', 'Quote Sent')), '[]'::jsonb)
    ) into snapshot from public.leads where organisation_id = target_organisation;
  elsif agent_slug = 'derrick' then
    select jsonb_build_object(
      'jobs', coalesce(jsonb_agg(jsonb_build_object('id', id, 'stage', stage, 'deposit', deposit, 'deposit_paid', deposit_paid, 'balance', balance, 'updated_at', updated_at) order by id), '[]'::jsonb)
    ) into snapshot from public.leads where organisation_id = target_organisation;
  elsif agent_slug = 'big-john' then
    select jsonb_build_object(
      'jobs', coalesce(jsonb_agg(jsonb_build_object('id', id, 'stage', stage, 'assigned_to', assigned_to, 'start_date', start_date, 'end_date', end_date, 'tasks', tasks, 'materials', materials, 'updated_at', updated_at) order by id)
        filter (where stage in ('Won', 'Scheduled', 'In Progress')), '[]'::jsonb)
    ) into snapshot from public.leads where organisation_id = target_organisation;
  else
    select jsonb_build_object(
      'jobs', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'stage', stage, 'assigned_to', assigned_to, 'start_date', start_date, 'end_date', end_date, 'deposit', deposit, 'deposit_paid', deposit_paid, 'balance', balance, 'tasks', tasks, 'updated_at', updated_at) order by id), '[]'::jsonb) from public.leads where organisation_id = target_organisation),
      'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'completed', completed, 'due_date', due_date, 'priority', priority, 'assigned_to', assigned_to) order by id), '[]'::jsonb) from public.general_tasks where organisation_id = target_organisation)
    ) into snapshot;
  end if;

  current_fingerprint := md5(coalesce(snapshot, '{}'::jsonb)::text);
  previous_fingerprint := target_agent.metadata->>'last_snapshot_fingerprint';
  return jsonb_build_object(
    'changed', previous_fingerprint is distinct from current_fingerprint,
    'fingerprint', current_fingerprint,
    'workflow', workflow_name,
    'last_success_at', target_agent.last_success_at,
    'instruction', case when previous_fingerprint is distinct from current_fingerprint
      then 'Run the relevant ProLine review, then include this fingerprint in the successful check-in.'
      else 'Nothing material changed. Stop without running a full review or producing a duplicate alert.' end
  );
end;
$$;

create or replace function public.proline_agent_checkin_v2(
  target_organisation uuid,
  agent_slug text,
  external_run_id text,
  run_status text,
  run_summary text,
  run_items jsonb default '[]'::jsonb,
  run_trigger text default 'scheduled',
  next_run timestamptz default null,
  run_error text default null,
  snapshot_fingerprint text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent_id uuid;
  created_run_id uuid;
  word_count integer;
begin
  select id into target_agent_id from public.ai_agents
  where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent_id is null then raise exception 'active agent not found'; end if;
  word_count := coalesce(array_length(regexp_split_to_array(trim(coalesce(run_summary, '')), E'\\s+'), 1), 0);
  if word_count > 300 then raise exception 'a check-in summary may contain no more than 300 words'; end if;
  if length(coalesce(snapshot_fingerprint, '')) > 80 then raise exception 'invalid snapshot fingerprint'; end if;

  created_run_id := public.proline_agent_checkin(
    target_organisation, agent_slug, external_run_id, run_status, run_summary,
    run_items, run_trigger, next_run, run_error
  );
  if run_status in ('succeeded', 'partial') and nullif(snapshot_fingerprint, '') is not null then
    update public.ai_agents set
      metadata = jsonb_set(coalesce(metadata, '{}'::jsonb), '{last_snapshot_fingerprint}', to_jsonb(snapshot_fingerprint), true),
      updated_at = now()
    where id = target_agent_id;
  end if;
  return created_run_id;
end;
$$;

-- Evidence is mandatory for actions that claim work happened.
drop function if exists public.proline_add_job_note(uuid, text, text, text);
create function public.proline_add_job_note(
  target_organisation uuid,
  agent_slug text,
  job_id text,
  note_content text,
  action_evidence text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  target_job public.leads%rowtype;
  note_id text := gen_random_uuid()::text;
  safe_content text := trim(coalesce(note_content, ''));
  safe_evidence text := trim(coalesce(action_evidence, ''));
  note jsonb;
begin
  if length(safe_content) < 1 or length(safe_content) > 2000 then raise exception 'invalid note content'; end if;
  if length(safe_evidence) < 5 or length(safe_evidence) > 1000 then raise exception 'clear evidence is required'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active agent not found'; end if;
  select * into target_job from public.leads where organisation_id = target_organisation and id = job_id for update;
  if target_job.id is null then raise exception 'job not found'; end if;

  note := jsonb_build_object('id', note_id, 'content', safe_content, 'date', current_date::text, 'author', target_agent.name || ' (AI)');
  update public.leads set notes = jsonb_build_array(note) || coalesce(notes, '[]'::jsonb), updated_at = now()::text
  where organisation_id = target_organisation and id = job_id;
  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'add_job_note', 'job', job_id,
    'Added an attributed internal note to ' || coalesce(nullif(target_job.job_ref, ''), job_id),
    jsonb_build_object('note_id', note_id, 'job_ref', target_job.job_ref, 'evidence', safe_evidence));
  return note_id;
end;
$$;

drop function if exists public.proline_complete_job_task(uuid, text, text, text, text);
create function public.proline_complete_job_task(
  target_organisation uuid,
  agent_slug text,
  job_id text,
  task_id text,
  completion_note text default null,
  action_evidence text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  target_job public.leads%rowtype;
  task_title text;
  updated_tasks jsonb;
  safe_evidence text := trim(coalesce(action_evidence, ''));
begin
  if length(coalesce(completion_note, '')) > 1000 then raise exception 'completion note is too long'; end if;
  if length(safe_evidence) < 5 or length(safe_evidence) > 1000 then raise exception 'clear evidence is required'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active agent not found'; end if;
  select * into target_job from public.leads where organisation_id = target_organisation and id = job_id for update;
  if target_job.id is null then raise exception 'job not found'; end if;
  select item->>'title' into task_title from jsonb_array_elements(coalesce(target_job.tasks, '[]'::jsonb)) item where item->>'id' = task_id limit 1;
  if task_title is null then raise exception 'job task not found'; end if;

  select jsonb_agg(case when item->>'id' = task_id then
    case when nullif(trim(coalesce(completion_note, '')), '') is null
      then jsonb_set(jsonb_set(item, '{completed}', 'true'::jsonb, true), '{completedDate}', to_jsonb(current_date::text), true)
      else jsonb_set(jsonb_set(jsonb_set(item, '{completed}', 'true'::jsonb, true), '{completedDate}', to_jsonb(current_date::text), true), '{notes}', to_jsonb(trim(completion_note)), true)
    end else item end) into updated_tasks
  from jsonb_array_elements(coalesce(target_job.tasks, '[]'::jsonb)) item;
  update public.leads set tasks = coalesce(updated_tasks, '[]'::jsonb), updated_at = now()::text
  where organisation_id = target_organisation and id = job_id;
  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'complete_job_task', 'job_task', task_id,
    'Completed job task: ' || left(task_title, 180),
    jsonb_build_object('job_id', job_id, 'job_ref', target_job.job_ref, 'completion_note', completion_note, 'evidence', safe_evidence));
  return true;
end;
$$;

drop function if exists public.proline_complete_general_task(uuid, text, text, text);
create function public.proline_complete_general_task(
  target_organisation uuid,
  agent_slug text,
  task_id text,
  completion_note text default null,
  action_evidence text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  target_task public.general_tasks%rowtype;
  safe_evidence text := trim(coalesce(action_evidence, ''));
begin
  if length(coalesce(completion_note, '')) > 1000 then raise exception 'completion note is too long'; end if;
  if length(safe_evidence) < 5 or length(safe_evidence) > 1000 then raise exception 'clear evidence is required'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active agent not found'; end if;
  select * into target_task from public.general_tasks where organisation_id = target_organisation and id = task_id for update;
  if target_task.id is null then raise exception 'task not found'; end if;
  update public.general_tasks set completed = true, completed_date = current_date::text,
    notes = case when nullif(trim(coalesce(completion_note, '')), '') is null then notes
      else concat_ws(E'\n', nullif(notes, ''), '[Completed by ' || target_agent.name || ' (AI)] ' || trim(completion_note)) end
  where organisation_id = target_organisation and id = task_id;
  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'complete_general_task', 'general_task', task_id,
    'Completed general task: ' || left(target_task.title, 180),
    jsonb_build_object('completion_note', completion_note, 'evidence', safe_evidence));
  return true;
end;
$$;

create or replace function public.proline_create_verified_lead(
  target_organisation uuid,
  agent_slug text,
  lead_source text,
  source_event_id text,
  customer_name text,
  customer_phone text default '',
  customer_email text default '',
  customer_address text default '',
  requested_job_type text default 'Roof Repair',
  source_url text default null,
  action_evidence text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  existing_lead_id text;
  new_lead_id text := gen_random_uuid()::text;
  new_job_ref text := 'JOB-' || to_char(clock_timestamp() at time zone 'Europe/London', 'YYMMDD-HH24MISS-') || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
  safe_evidence text := trim(coalesce(action_evidence, ''));
  source_label text;
begin
  if lead_source not in ('website', 'mybuilder_shortlisted') then raise exception 'invalid verified lead source'; end if;
  if length(trim(coalesce(source_event_id, ''))) < 3 or length(source_event_id) > 180 then raise exception 'invalid source event'; end if;
  if length(trim(coalesce(customer_name, ''))) < 1 or length(customer_name) > 180 then raise exception 'invalid customer name'; end if;
  if length(trim(coalesce(requested_job_type, ''))) < 1 or length(requested_job_type) > 180 then raise exception 'invalid job type'; end if;
  if length(safe_evidence) < 5 or length(safe_evidence) > 1000 then raise exception 'verification evidence is required'; end if;
  if lead_source = 'mybuilder_shortlisted' and length(trim(coalesce(customer_phone, ''))) = 0 and length(trim(coalesce(customer_email, ''))) = 0 then
    raise exception 'MyBuilder contact details must have been shared before a CRM lead is created';
  end if;
  select * into target_agent from public.ai_agents
  where organisation_id = target_organisation and slug = 'rodney' and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active Rodney agent not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(target_organisation::text || ':' || lead_source || ':' || source_event_id, 0));
  select lead_id into existing_lead_id from public.ai_verified_lead_events
  where organisation_id = target_organisation and source = lead_source and ai_verified_lead_events.source_event_id = proline_create_verified_lead.source_event_id;
  if existing_lead_id is not null then
    return jsonb_build_object('lead_id', existing_lead_id, 'job_ref', (select job_ref from public.leads where id = existing_lead_id), 'duplicate', true);
  end if;

  source_label := case when lead_source = 'website' then 'Website' else 'MyBuilder' end;
  insert into public.leads (
    id, organisation_id, job_ref, name, phone, email, address, job_type, stage, value, deposit,
    deposit_paid, balance, source, assigned_to, progress, tasks, photos, notes, files, materials,
    mybuilder_url, created_at, updated_at
  ) values (
    new_lead_id, target_organisation, new_job_ref, trim(customer_name), trim(coalesce(customer_phone, '')),
    trim(coalesce(customer_email, '')), trim(coalesce(customer_address, '')), trim(requested_job_type),
    'New Lead', 0, 0, false, 0, source_label, '', 0, '[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'content', 'Verified ' || source_label || ' enquiry added by Rodney. Evidence: ' || safe_evidence, 'date', current_date::text, 'author', 'Rodney (AI)')),
    '[]'::jsonb, '[]'::jsonb, case when lead_source = 'mybuilder_shortlisted' then nullif(trim(coalesce(source_url, '')), '') else null end,
    now()::text, now()::text
  );
  insert into public.ai_verified_lead_events (organisation_id, agent_id, source, source_event_id, lead_id, evidence)
  values (target_organisation, target_agent.id, lead_source, trim(source_event_id), new_lead_id, safe_evidence);
  return jsonb_build_object('lead_id', new_lead_id, 'job_ref', new_job_ref, 'duplicate', false);
end;
$$;

-- Only active agents may create/update their own internal tasks or submit proposals.
create or replace function public.proline_create_internal_task(
  target_organisation uuid, agent_slug text, dedupe_key text, task_title text,
  due_on date default null, task_priority text default 'medium', task_category text default 'AI agent', task_notes text default null
)
returns text language plpgsql security definer set search_path = public as $$
declare target_agent_id uuid; task_id text;
begin
  if task_priority not in ('low', 'medium', 'high') then raise exception 'invalid priority'; end if;
  if length(trim(task_title)) < 1 or length(task_title) > 180 then raise exception 'invalid task title'; end if;
  if length(trim(dedupe_key)) < 1 or length(dedupe_key) > 180 then raise exception 'invalid dedupe key'; end if;
  select id into target_agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent_id is null then raise exception 'active agent not found'; end if;
  perform pg_advisory_xact_lock(hashtextextended(target_organisation::text || ':' || dedupe_key, 0));
  select link.task_id into task_id from public.ai_internal_task_links link where link.organisation_id = target_organisation and link.dedupe_key = proline_create_internal_task.dedupe_key;
  if task_id is not null then return task_id; end if;
  task_id := gen_random_uuid()::text;
  insert into public.general_tasks (id, organisation_id, title, completed, due_date, priority, category, notes, created_at, assigned_to)
  values (task_id, target_organisation, trim(task_title), false, due_on::text, task_priority, left(task_category, 80), left(task_notes, 2000), current_date::text, '[]'::jsonb);
  insert into public.ai_internal_task_links (organisation_id, task_id, agent_id, dedupe_key) values (target_organisation, task_id, target_agent_id, trim(dedupe_key));
  return task_id;
end; $$;

create or replace function public.proline_update_internal_task(
  target_organisation uuid, agent_slug text, task_id text, mark_completed boolean default null, due_on date default null, task_notes text default null
)
returns boolean language plpgsql security definer set search_path = public as $$
declare target_agent_id uuid; changed integer;
begin
  select id into target_agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if target_agent_id is null then raise exception 'active agent not found'; end if;
  update public.general_tasks task set completed = coalesce(mark_completed, task.completed),
    completed_date = case when mark_completed is true then current_date::text when mark_completed is false then null else task.completed_date end,
    due_date = coalesce(due_on::text, task.due_date), notes = coalesce(left(task_notes, 2000), task.notes)
  where task.organisation_id = target_organisation and task.id = proline_update_internal_task.task_id
    and exists (select 1 from public.ai_internal_task_links link where link.organisation_id = target_organisation and link.task_id = task.id and link.agent_id = target_agent_id);
  get diagnostics changed = row_count;
  return changed = 1;
end; $$;

create or replace function public.proline_submit_action_proposal(
  target_organisation uuid, agent_slug text, proposal_category text, proposal_title text,
  proposal_summary text, proposal_risk text default 'medium', proposal_sources jsonb default '[]'::jsonb, proposal_action jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = public as $$
declare agent_id uuid; proposal_id uuid;
begin
  if proposal_category not in ('customer_message', 'schedule', 'job_change', 'finance', 'purchase', 'delete', 'legal', 'complaint', 'other') then raise exception 'invalid category'; end if;
  if proposal_risk not in ('low', 'medium', 'high', 'critical') then raise exception 'invalid risk'; end if;
  select id into agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug and active = true;
  if agent_id is null then raise exception 'active agent not found'; end if;
  insert into public.ai_action_proposals (organisation_id, agent_id, category, title, summary, risk_level, source_refs, proposed_action)
  values (target_organisation, agent_id, proposal_category, left(proposal_title, 180), left(proposal_summary, 2000), proposal_risk,
    coalesce(proposal_sources, '[]'::jsonb), coalesce(proposal_action, '{}'::jsonb)) returning id into proposal_id;
  return proposal_id;
end; $$;

revoke all on function private.seed_staged_ai_workforce(uuid) from public, anon, authenticated;
revoke all on function public.proline_workforce_change_check(uuid, text, text) from public, anon, authenticated;
revoke all on function public.proline_agent_checkin_v2(uuid, text, text, text, text, jsonb, text, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.proline_add_job_note(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_complete_job_task(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_complete_general_task(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_create_verified_lead(uuid, text, text, text, text, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) from public, anon, authenticated;
revoke all on function public.proline_submit_action_proposal(uuid, text, text, text, text, text, jsonb, jsonb) from public, anon, authenticated;

grant execute on function public.proline_workforce_change_check(uuid, text, text) to service_role;
grant execute on function public.proline_agent_checkin_v2(uuid, text, text, text, text, jsonb, text, timestamptz, text, text) to service_role;
grant execute on function public.proline_add_job_note(uuid, text, text, text, text) to service_role;
grant execute on function public.proline_complete_job_task(uuid, text, text, text, text, text) to service_role;
grant execute on function public.proline_complete_general_task(uuid, text, text, text, text) to service_role;
grant execute on function public.proline_create_verified_lead(uuid, text, text, text, text, text, text, text, text, text, text) to service_role;
grant execute on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) to service_role;
grant execute on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) to service_role;
grant execute on function public.proline_submit_action_proposal(uuid, text, text, text, text, text, jsonb, jsonb) to service_role;

do $$
declare table_name text;
begin
  foreach table_name in array array['ai_workforce_settings', 'ai_agent_acceptance', 'ai_verified_lead_events'] loop
    if not exists (
      select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name
    ) then execute format('alter publication supabase_realtime add table public.%I', table_name); end if;
  end loop;
end $$;

commit;
