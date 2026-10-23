-- Controlled employee-style actions for the Stace pilot.
-- These functions deliberately exclude customer communication, scheduling,
-- job-stage, ownership, finance, purchase and deletion capabilities.

begin;

create table if not exists public.ai_agent_actions (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  action_type text not null check (action_type in ('complete_job_task', 'complete_general_task', 'add_job_note')),
  entity_type text not null check (entity_type in ('job', 'job_task', 'general_task')),
  entity_id text not null,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists ai_agent_actions_recent_idx
  on public.ai_agent_actions (organisation_id, created_at desc);

alter table public.ai_agent_actions enable row level security;
drop policy if exists ai_agent_actions_admin_select on public.ai_agent_actions;
create policy ai_agent_actions_admin_select on public.ai_agent_actions for select to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());
revoke all on public.ai_agent_actions from public, anon, authenticated;
grant select on public.ai_agent_actions to authenticated;

-- Replace the pilot check-in function to remove the provider_run_id name
-- collision that prevented Grok runs from appearing in the Virtual Office.
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
  if run_status not in ('queued', 'running', 'succeeded', 'partial', 'failed', 'cancelled') then raise exception 'invalid run status'; end if;
  if run_trigger not in ('scheduled', 'manual', 'webhook', 'comparison') then raise exception 'invalid run trigger'; end if;
  if jsonb_typeof(safe_items) <> 'array' or jsonb_array_length(safe_items) > 8 then raise exception 'a check-in may contain no more than eight items'; end if;
  if length(coalesce(run_summary, '')) > 3000 then raise exception 'check-in summary is too long'; end if;

  select * into target_agent from public.ai_agents
  where organisation_id = target_organisation and slug = agent_slug;
  if target_agent.id is null then raise exception 'agent not found'; end if;

  insert into public.ai_agent_runs (
    organisation_id, agent_id, provider_run_id, trigger_type, status,
    summary, items, item_count, error, finished_at
  ) values (
    target_organisation, target_agent.id, nullif(proline_agent_checkin.provider_run_id, ''), run_trigger, run_status,
    nullif(run_summary, ''), safe_items, jsonb_array_length(safe_items), nullif(run_error, ''),
    case when run_status in ('succeeded', 'partial', 'failed', 'cancelled') then now() else null end
  )
  on conflict do nothing
  returning id into run_id;

  if run_id is null and nullif(proline_agent_checkin.provider_run_id, '') is not null then
    update public.ai_agent_runs existing set
      status = run_status,
      summary = nullif(run_summary, ''),
      items = safe_items,
      item_count = jsonb_array_length(safe_items),
      error = nullif(run_error, ''),
      finished_at = case when run_status in ('succeeded', 'partial', 'failed', 'cancelled') then now() else null end
    where existing.organisation_id = target_organisation
      and existing.agent_id = target_agent.id
      and existing.provider_run_id = proline_agent_checkin.provider_run_id
    returning existing.id into run_id;
  end if;

  if run_id is null then raise exception 'check-in could not be recorded'; end if;

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

create or replace function public.proline_add_job_note(
  target_organisation uuid,
  agent_slug text,
  job_id text,
  note_content text
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
  note jsonb;
begin
  if length(safe_content) < 1 or length(safe_content) > 2000 then raise exception 'invalid note content'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if target_agent.id is null then raise exception 'agent not found'; end if;
  select * into target_job from public.leads where organisation_id = target_organisation and id = job_id for update;
  if target_job.id is null then raise exception 'job not found'; end if;

  note := jsonb_build_object(
    'id', note_id,
    'content', safe_content,
    'date', current_date::text,
    'author', target_agent.name || ' (AI)'
  );
  update public.leads set
    notes = jsonb_build_array(note) || coalesce(notes, '[]'::jsonb),
    updated_at = now()::text
  where organisation_id = target_organisation and id = job_id;

  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'add_job_note', 'job', job_id,
    'Added an attributed internal note to ' || coalesce(nullif(target_job.job_ref, ''), job_id),
    jsonb_build_object('note_id', note_id, 'job_ref', target_job.job_ref));
  return note_id;
end;
$$;

create or replace function public.proline_complete_job_task(
  target_organisation uuid,
  agent_slug text,
  job_id text,
  task_id text,
  completion_note text default null
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
begin
  if length(coalesce(completion_note, '')) > 1000 then raise exception 'completion note is too long'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if target_agent.id is null then raise exception 'agent not found'; end if;
  select * into target_job from public.leads where organisation_id = target_organisation and id = job_id for update;
  if target_job.id is null then raise exception 'job not found'; end if;
  select item->>'title' into task_title from jsonb_array_elements(coalesce(target_job.tasks, '[]'::jsonb)) item where item->>'id' = task_id limit 1;
  if task_title is null then raise exception 'job task not found'; end if;

  select jsonb_agg(
    case when item->>'id' = task_id then
      case when nullif(trim(coalesce(completion_note, '')), '') is null
        then jsonb_set(jsonb_set(item, '{completed}', 'true'::jsonb, true), '{completedDate}', to_jsonb(current_date::text), true)
        else jsonb_set(jsonb_set(jsonb_set(item, '{completed}', 'true'::jsonb, true), '{completedDate}', to_jsonb(current_date::text), true), '{notes}', to_jsonb(trim(completion_note)), true)
      end
    else item end
  ) into updated_tasks
  from jsonb_array_elements(coalesce(target_job.tasks, '[]'::jsonb)) item;

  update public.leads set tasks = coalesce(updated_tasks, '[]'::jsonb), updated_at = now()::text
  where organisation_id = target_organisation and id = job_id;
  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'complete_job_task', 'job_task', task_id,
    'Completed job task: ' || left(task_title, 180),
    jsonb_build_object('job_id', job_id, 'job_ref', target_job.job_ref, 'completion_note', completion_note));
  return true;
end;
$$;

create or replace function public.proline_complete_general_task(
  target_organisation uuid,
  agent_slug text,
  task_id text,
  completion_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_agent public.ai_agents%rowtype;
  target_task public.general_tasks%rowtype;
begin
  if length(coalesce(completion_note, '')) > 1000 then raise exception 'completion note is too long'; end if;
  select * into target_agent from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if target_agent.id is null then raise exception 'agent not found'; end if;
  select * into target_task from public.general_tasks where organisation_id = target_organisation and id = task_id for update;
  if target_task.id is null then raise exception 'task not found'; end if;

  update public.general_tasks set
    completed = true,
    completed_date = current_date::text,
    notes = case when nullif(trim(coalesce(completion_note, '')), '') is null then notes
      else concat_ws(E'\n', nullif(notes, ''), '[Completed by ' || target_agent.name || ' (AI)] ' || trim(completion_note)) end
  where organisation_id = target_organisation and id = task_id;
  insert into public.ai_agent_actions (organisation_id, agent_id, action_type, entity_type, entity_id, summary, details)
  values (target_organisation, target_agent.id, 'complete_general_task', 'general_task', task_id,
    'Completed general task: ' || left(target_task.title, 180),
    jsonb_build_object('completion_note', completion_note));
  return true;
end;
$$;

revoke all on function public.proline_agent_checkin(uuid, text, text, text, text, jsonb, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.proline_add_job_note(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_complete_job_task(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_complete_general_task(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.proline_agent_checkin(uuid, text, text, text, text, jsonb, text, timestamptz, text) to service_role;
grant execute on function public.proline_add_job_note(uuid, text, text, text) to service_role;
grant execute on function public.proline_complete_job_task(uuid, text, text, text, text) to service_role;
grant execute on function public.proline_complete_general_task(uuid, text, text, text) to service_role;

commit;
