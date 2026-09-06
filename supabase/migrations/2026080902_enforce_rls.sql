-- ProLine CRM Auth/RLS phase 2: enforcement.
-- Run only after every non-casual legacy account has an active Auth profile.
begin;

do $$
begin
  if exists (
    select 1 from public.app_users u
    where u.role <> 'casual'
      and not exists (select 1 from public.profiles p where p.legacy_user_id = u.id and p.active)
  ) then
    raise exception 'RLS cutover stopped: one or more legacy staff accounts has no active Auth profile';
  end if;
end $$;

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.current_organisation_id()
returns uuid language sql stable security definer set search_path = public
as $$ select organisation_id from public.profiles where id = auth.uid() and active limit 1 $$;

create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce((select role = 'admin' from public.profiles where id = auth.uid() and active), false) $$;

create or replace function private.current_worker_ids()
returns text[] language sql stable security definer set search_path = public
as $$ select array_remove(array[auth.uid()::text, legacy_user_id], null) from public.profiles where id = auth.uid() and active $$;

grant usage on schema private to authenticated;
grant execute on function private.current_organisation_id() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.current_worker_ids() to authenticated;

do $$
declare table_name text;
begin
  foreach table_name in array array['leads','contacts','general_tasks','push_subscriptions'] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I alter column organisation_id set default private.current_organisation_id()', table_name);
      execute format('alter table public.%I alter column organisation_id set not null', table_name);
      execute format('alter table public.%I enable row level security', table_name);
      execute format('drop policy if exists organisation_select on public.%I', table_name);
      execute format('drop policy if exists organisation_insert on public.%I', table_name);
      execute format('drop policy if exists organisation_update on public.%I', table_name);
      execute format('drop policy if exists organisation_delete on public.%I', table_name);
      execute format('create policy organisation_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id())', table_name);
      execute format('create policy organisation_insert on public.%I for insert to authenticated with check (organisation_id = private.current_organisation_id())', table_name);
      execute format('create policy organisation_update on public.%I for update to authenticated using (organisation_id = private.current_organisation_id()) with check (organisation_id = private.current_organisation_id())', table_name);
      execute format('create policy organisation_delete on public.%I for delete to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin())', table_name);
      execute format('revoke all on public.%I from anon', table_name);
      execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    end if;
  end loop;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array['payment_runs','worker_payments'] loop
    execute format('alter table public.%I alter column organisation_id set default private.current_organisation_id()', table_name);
    execute format('alter table public.%I alter column organisation_id set not null', table_name);
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists finance_select on public.%I', table_name);
    execute format('drop policy if exists finance_manage on public.%I', table_name);
    execute format('create policy finance_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id())', table_name);
    execute format('create policy finance_manage on public.%I for all to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin()) with check (organisation_id = private.current_organisation_id() and private.is_admin())', table_name);
    execute format('revoke all on public.%I from anon', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

alter table public.timesheet_entries alter column organisation_id set default private.current_organisation_id();
alter table public.timesheet_entries alter column organisation_id set not null;
alter table public.timesheet_entries enable row level security;
drop policy if exists timesheet_select on public.timesheet_entries;
drop policy if exists timesheet_insert on public.timesheet_entries;
drop policy if exists timesheet_update on public.timesheet_entries;
drop policy if exists timesheet_delete on public.timesheet_entries;
create policy timesheet_select on public.timesheet_entries for select to authenticated
  using (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
create policy timesheet_insert on public.timesheet_entries for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
create policy timesheet_update on public.timesheet_entries for update to authenticated
  using (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()))
  with check (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
create policy timesheet_delete on public.timesheet_entries for delete to authenticated
  using (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
revoke all on public.timesheet_entries from anon;
grant select, insert, update, delete on public.timesheet_entries to authenticated;

alter table public.profiles enable row level security;
drop policy if exists profile_select on public.profiles;
drop policy if exists profile_update_self on public.profiles;
drop policy if exists profile_manage_admin on public.profiles;
create policy profile_select on public.profiles for select to authenticated
  using (organisation_id = private.current_organisation_id());
create policy profile_update_self on public.profiles for update to authenticated
  using (id = auth.uid() and active) with check (id = auth.uid() and organisation_id = private.current_organisation_id());
create policy profile_manage_admin on public.profiles for all to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin())
  with check (organisation_id = private.current_organisation_id() and private.is_admin());
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (name, username, day_rate, cis_rate, utr_number, bank_name, bank_account_number, bank_sort_code) on public.profiles to authenticated;

alter table public.app_users enable row level security;
revoke all on public.app_users from anon, authenticated;

drop policy if exists attachment_select on storage.objects;
drop policy if exists attachment_insert on storage.objects;
drop policy if exists attachment_update on storage.objects;
drop policy if exists attachment_delete on storage.objects;
create policy attachment_select on storage.objects for select to authenticated
  using (bucket_id = 'crm-attachments' and (storage.foldername(name))[1] = private.current_organisation_id()::text);
create policy attachment_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'crm-attachments' and (storage.foldername(name))[1] = private.current_organisation_id()::text);
create policy attachment_update on storage.objects for update to authenticated
  using (bucket_id = 'crm-attachments' and (storage.foldername(name))[1] = private.current_organisation_id()::text)
  with check (bucket_id = 'crm-attachments' and (storage.foldername(name))[1] = private.current_organisation_id()::text);
create policy attachment_delete on storage.objects for delete to authenticated
  using (bucket_id = 'crm-attachments' and (storage.foldername(name))[1] = private.current_organisation_id()::text);

commit;
