-- Keep bot task ownership outside the worker-editable general_tasks table.

begin;

create table if not exists public.ai_internal_task_links (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  task_id text not null references public.general_tasks(id) on delete cascade,
  agent_id uuid not null references public.ai_agents(id) on delete cascade,
  dedupe_key text not null,
  created_at timestamptz not null default now(),
  unique (organisation_id, task_id),
  unique (organisation_id, dedupe_key)
);

alter table public.ai_internal_task_links enable row level security;
drop policy if exists ai_workforce_admin_select on public.ai_internal_task_links;
create policy ai_workforce_admin_select on public.ai_internal_task_links for select to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());
revoke all on public.ai_internal_task_links from anon, authenticated;
grant select on public.ai_internal_task_links to authenticated;

-- The earlier compatibility columns remain in place to keep this migration
-- non-destructive, but the security boundary never reads or trusts them.
comment on column public.general_tasks.ai_source_agent_id is 'Compatibility only; authoritative bot ownership is stored in ai_internal_task_links.';
comment on column public.general_tasks.ai_dedupe_key is 'Compatibility only; authoritative bot deduplication is stored in ai_internal_task_links.';

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
  target_agent_id uuid;
  task_id text;
begin
  if task_priority not in ('low', 'medium', 'high') then raise exception 'invalid priority'; end if;
  if length(trim(task_title)) < 1 or length(task_title) > 180 then raise exception 'invalid task title'; end if;
  if length(trim(dedupe_key)) < 1 or length(dedupe_key) > 180 then raise exception 'invalid dedupe key'; end if;
  select id into target_agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if target_agent_id is null then raise exception 'agent not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(target_organisation::text || ':' || dedupe_key, 0));
  select link.task_id into task_id from public.ai_internal_task_links link
  where link.organisation_id = target_organisation and link.dedupe_key = proline_create_internal_task.dedupe_key;
  if task_id is not null then return task_id; end if;

  task_id := gen_random_uuid()::text;
  insert into public.general_tasks (
    id, organisation_id, title, completed, due_date, priority, category,
    notes, created_at, assigned_to
  ) values (
    task_id, target_organisation, trim(task_title), false, due_on::text, task_priority,
    left(task_category, 80), left(task_notes, 2000), current_date::text, '[]'::jsonb
  );
  insert into public.ai_internal_task_links (organisation_id, task_id, agent_id, dedupe_key)
  values (target_organisation, task_id, target_agent_id, trim(dedupe_key));
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
  target_agent_id uuid;
  changed integer;
begin
  select id into target_agent_id from public.ai_agents where organisation_id = target_organisation and slug = agent_slug;
  if target_agent_id is null then raise exception 'agent not found'; end if;
  update public.general_tasks task set
    completed = coalesce(mark_completed, task.completed),
    completed_date = case when mark_completed is true then current_date::text when mark_completed is false then null else task.completed_date end,
    due_date = coalesce(due_on::text, task.due_date),
    notes = coalesce(left(task_notes, 2000), task.notes)
  where task.organisation_id = target_organisation
    and task.id = proline_update_internal_task.task_id
    and exists (
      select 1 from public.ai_internal_task_links link
      where link.organisation_id = target_organisation
        and link.task_id = task.id
        and link.agent_id = target_agent_id
    );
  get diagnostics changed = row_count;
  return changed = 1;
end;
$$;

revoke all on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) from public, anon, authenticated;
revoke all on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) from public, anon, authenticated;
grant execute on function public.proline_create_internal_task(uuid, text, text, text, date, text, text, text) to service_role;
grant execute on function public.proline_update_internal_task(uuid, text, text, boolean, date, text) to service_role;

commit;
