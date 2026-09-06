begin;

alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('admin', 'worker', 'labourer', 'user', 'casual'));

create table if not exists public.worker_invitations (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  email text not null,
  role text not null default 'worker' check (role in ('admin', 'worker', 'labourer')),
  token_hash text not null unique,
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists worker_invitations_org_created_idx
  on public.worker_invitations (organisation_id, created_at desc);

alter table public.worker_invitations enable row level security;
drop policy if exists worker_invitation_admin_select on public.worker_invitations;
drop policy if exists worker_invitation_admin_insert on public.worker_invitations;
drop policy if exists worker_invitation_admin_delete on public.worker_invitations;
create policy worker_invitation_admin_select on public.worker_invitations for select to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());
create policy worker_invitation_admin_insert on public.worker_invitations for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and created_by = auth.uid() and private.is_admin());
create policy worker_invitation_admin_delete on public.worker_invitations for delete to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin());
revoke all on public.worker_invitations from anon, authenticated;
grant select, insert, delete on public.worker_invitations to authenticated;

commit;
