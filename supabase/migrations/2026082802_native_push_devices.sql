begin;

create table if not exists public.native_push_devices (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null default private.current_organisation_id() references public.organisations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_token text not null unique,
  platform text not null check (platform in ('ios', 'macos')),
  environment text not null check (environment in ('development', 'production')),
  bundle_id text not null,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.native_push_devices enable row level security;
drop policy if exists native_push_select_self on public.native_push_devices;
drop policy if exists native_push_insert_self on public.native_push_devices;
drop policy if exists native_push_update_self on public.native_push_devices;
drop policy if exists native_push_delete_self on public.native_push_devices;
create policy native_push_select_self on public.native_push_devices for select to authenticated
  using (organisation_id = private.current_organisation_id() and user_id = auth.uid());
create policy native_push_insert_self on public.native_push_devices for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and user_id = auth.uid());
create policy native_push_update_self on public.native_push_devices for update to authenticated
  using (organisation_id = private.current_organisation_id() and user_id = auth.uid())
  with check (organisation_id = private.current_organisation_id() and user_id = auth.uid());
create policy native_push_delete_self on public.native_push_devices for delete to authenticated
  using (organisation_id = private.current_organisation_id() and user_id = auth.uid());
revoke all on public.native_push_devices from anon, authenticated;
grant select, insert, update, delete on public.native_push_devices to authenticated;

commit;
