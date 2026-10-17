-- Repair production schema drift for the read-only ProLine MCP connector.
--
-- The Auth/RLS migration versions are present in the remote migration ledger,
-- but the legacy leads and general_tasks tables do not have organisation_id.
-- Keep this repair deliberately narrower than the deferred RLS rollout: assign
-- the existing single organisation, preserve legacy app writes with a default,
-- and do not change RLS or table grants.
begin;

do $$
declare
  organisation_count integer;
  existing_organisation uuid;
begin
  select count(*), min(id::text)::uuid
    into organisation_count, existing_organisation
    from public.organisations;

  if organisation_count <> 1 then
    raise exception 'MCP organisation repair requires exactly one organisation; found %', organisation_count;
  end if;

  if existing_organisation <> '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'MCP organisation repair found an unexpected organisation: %', existing_organisation;
  end if;

  if exists (
    select 1 from public.profiles
    where organisation_id is distinct from existing_organisation
  ) then
    raise exception 'MCP organisation repair stopped because a profile belongs to another organisation';
  end if;
end $$;

alter table public.leads
  add column if not exists organisation_id uuid references public.organisations(id);
alter table public.general_tasks
  add column if not exists organisation_id uuid references public.organisations(id);

update public.leads
set organisation_id = '00000000-0000-0000-0000-000000000001'::uuid
where organisation_id is null;

update public.general_tasks
set organisation_id = '00000000-0000-0000-0000-000000000001'::uuid
where organisation_id is null;

alter table public.leads
  alter column organisation_id set default '00000000-0000-0000-0000-000000000001'::uuid,
  alter column organisation_id set not null;

alter table public.general_tasks
  alter column organisation_id set default '00000000-0000-0000-0000-000000000001'::uuid,
  alter column organisation_id set not null;

commit;
