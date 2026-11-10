-- Preserve the existing named assignment while allowing extra team members.
begin;
create table public.job_team_members (
  organisation_id uuid not null,
  lead_id text not null references public.leads(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (lead_id, user_id)
);
create index job_team_members_user_idx on public.job_team_members (organisation_id, user_id, lead_id);
alter table public.job_team_members enable row level security;
revoke all on public.job_team_members from public, anon, authenticated;
grant select, insert, delete on public.job_team_members to authenticated;

-- Validate both ends on every insertion, even for administrators.
create policy team_select on public.job_team_members for select to authenticated
  using (organisation_id = private.current_organisation_id() and (private.is_admin() or user_id = auth.uid()));
create policy team_insert on public.job_team_members for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and private.is_admin()
    and exists (select 1 from public.leads l where l.id = lead_id and l.organisation_id = job_team_members.organisation_id)
    and exists (select 1 from public.profiles p where p.id = user_id and p.organisation_id = job_team_members.organisation_id and p.active));
create policy team_delete on public.job_team_members for delete to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());

create function private.can_access_job_team(job_id text) returns boolean
language sql stable security definer set search_path = ''
as $$ select exists (
  select 1 from public.job_team_members t
  join public.profiles p on p.id = t.user_id and p.organisation_id = t.organisation_id
  where t.lead_id = job_id and t.organisation_id = private.current_organisation_id()
    and t.user_id = auth.uid() and p.active
) $$;
revoke all on function private.can_access_job_team(text) from public;
grant execute on function private.can_access_job_team(text) to authenticated;

-- Replace the team atomically; never leave a partially saved selection.
create function public.set_job_team(p_lead_id text, p_user_ids uuid[]) returns void
language plpgsql security invoker set search_path = '' as $$
declare org_id uuid;
begin
  if not private.is_admin() then raise exception 'Only administrators can change the job team'; end if;
  select organisation_id into org_id from public.leads where id = p_lead_id
    and organisation_id = private.current_organisation_id();
  if org_id is null then raise exception 'Job not found'; end if;
  if exists (select 1 from unnest(coalesce(p_user_ids, array[]::uuid[])) id
    where not exists (select 1 from public.profiles p where p.id = id and p.organisation_id = org_id and p.active)) then
    raise exception 'A selected team member is unavailable';
  end if;
  delete from public.job_team_members where lead_id = p_lead_id and organisation_id = org_id;
  insert into public.job_team_members (organisation_id, lead_id, user_id)
    select org_id, p_lead_id, id from (select distinct unnest(coalesce(p_user_ids, array[]::uuid[])) id) members;
end $$;
revoke all on function public.set_job_team(text, uuid[]) from public, anon;
grant execute on function public.set_job_team(text, uuid[]) to authenticated;

drop policy organisation_select on public.leads;
create policy organisation_select on public.leads for select to authenticated
  using (organisation_id = private.current_organisation_id()
    and (private.can_access_assigned_lead(assigned_to) or private.can_access_job_team(id)));
drop policy organisation_update on public.leads;
create policy organisation_update on public.leads for update to authenticated
  using (organisation_id = private.current_organisation_id()
    and (private.can_access_assigned_lead(assigned_to) or private.can_access_job_team(id)))
  with check (organisation_id = private.current_organisation_id()
    and (private.can_access_assigned_lead(assigned_to) or private.can_access_job_team(id)));

create or replace function private.can_access_attachment(object_name text)
returns boolean language sql stable security definer set search_path = ''
as $$ select split_part(object_name, '/', 1) = private.current_organisation_id()::text
  and (private.is_admin() or (split_part(object_name, '/', 2) = 'leads' and exists (
    select 1 from public.leads l where l.id = split_part(object_name, '/', 3)
      and l.organisation_id = private.current_organisation_id()
      and (private.can_access_assigned_lead(l.assigned_to) or private.can_access_job_team(l.id))))) $$;
commit;
