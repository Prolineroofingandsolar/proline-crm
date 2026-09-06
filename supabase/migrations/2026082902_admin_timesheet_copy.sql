begin;

create table if not exists public.admin_timesheet_entries (
  id text primary key,
  user_id text not null,
  lead_id text not null default '',
  date text not null,
  type text not null check (type in ('full', 'half', 'off')),
  amount numeric not null default 0,
  created_at text not null,
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id),
  unique (organisation_id, user_id, date)
);

alter table public.admin_timesheet_entries enable row level security;
drop policy if exists admin_timesheet_copy_manage on public.admin_timesheet_entries;
create policy admin_timesheet_copy_manage on public.admin_timesheet_entries for all to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin())
  with check (organisation_id = private.current_organisation_id() and private.is_admin());
revoke all on public.admin_timesheet_entries from anon;
grant select, insert, update, delete on public.admin_timesheet_entries to authenticated;

commit;
