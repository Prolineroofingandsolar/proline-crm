begin;
do $$ begin
 if exists(select 1 from public.profiles where organisation_id <> '00000000-0000-0000-0000-000000000001'::uuid) then
 raise exception 'Multiple organisations require explicit backfill review'; end if;
end $$;
-- ProLine CRM Auth/RLS phase 1: additive foundation.
-- Safe to deploy before user invitations; this phase does not enable RLS.

create extension if not exists pgcrypto;

create table if not exists public.organisations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

insert into public.organisations (id, name)
values ('00000000-0000-0000-0000-000000000001', 'ProLine Roofing & Solar Ltd')
on conflict (id) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organisation_id uuid not null references public.organisations(id),
  legacy_user_id text unique,
  email text,
  username text,
  name text not null,
  role text not null default 'user' check (role in ('admin', 'user', 'casual')),
  active boolean not null default true,
  day_rate numeric,
  cis_rate integer default 20 check (cis_rate in (20, 30)),
  utr_number text,
  bank_name text,
  bank_account_number text,
  bank_sort_code text,
  created_at timestamptz not null default now()
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'leads', 'contacts', 'general_tasks', 'timesheet_entries',
    'payment_runs', 'worker_payments', 'push_subscriptions'
  ] loop
    if to_regclass('public.' || table_name) is not null then
      execute format('alter table public.%I add column if not exists organisation_id uuid references public.organisations(id)', table_name);
      execute format('update public.%I set organisation_id = $1 where organisation_id is null', table_name)
        using '00000000-0000-0000-0000-000000000001'::uuid;
    end if;
  end loop;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'crm-attachments', 'crm-attachments', false, 26214400,
  array['image/jpeg','image/png','image/heic','image/heif','image/webp','application/pdf','text/plain','text/csv','application/zip','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;


-- Before phase 2:
-- 1. Invite each non-casual app_users account through Supabase Auth.
-- 2. Insert one profiles row per invited user, setting legacy_user_id.
-- 3. Verify every active employee can sign in on web, macOS, and iOS.

-- Reconcile only unique existing staff-name matches. Roles and history are preserved.
update public.profiles p set legacy_user_id = u.id
from public.app_users u
where p.active and p.legacy_user_id is null and u.role <> 'casual'
  and lower(trim(p.name)) = lower(trim(u.name))
  and 1 = (select count(*) from public.profiles q where q.active and q.organisation_id=p.organisation_id and lower(trim(q.name))=lower(trim(u.name)))
  and 1 = (select count(*) from public.app_users v where v.role <> 'casual' and lower(trim(v.name))=lower(trim(u.name)))
  and not exists (select 1 from public.profiles existing where existing.legacy_user_id=u.id);
-- ProLine CRM Auth/RLS phase 2: enforcement.
-- Run only after every non-casual legacy account has an active Auth profile.

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

-- Narrow the previous organisation-wide employee access. No customer rows are changed.
-- Apply after the Auth/RLS cutover and verify with isolated admin/worker test accounts.
create or replace function private.can_access_assigned_lead(assigned_name text)
returns boolean language sql stable security definer set search_path = public
as $$
  select private.is_admin() or exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active
      and lower(trim(p.name)) = lower(trim(assigned_name))
      and 1 = (select count(*) from public.profiles other
        where other.organisation_id = p.organisation_id and other.active
          and lower(trim(other.name)) = lower(trim(p.name)))
  )
$$;
revoke all on function private.can_access_assigned_lead(text) from public;
grant execute on function private.can_access_assigned_lead(text) to authenticated;

drop policy if exists organisation_select on public.leads;
drop policy if exists organisation_insert on public.leads;
drop policy if exists organisation_update on public.leads;
create policy organisation_select on public.leads for select to authenticated
  using (organisation_id = private.current_organisation_id() and private.can_access_assigned_lead(assigned_to));
create policy organisation_insert on public.leads for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and private.is_admin());
create policy organisation_update on public.leads for update to authenticated
  using (organisation_id = private.current_organisation_id() and private.can_access_assigned_lead(assigned_to))
  with check (organisation_id = private.current_organisation_id() and private.can_access_assigned_lead(assigned_to));

-- Assignment is currently by display name. Prevent employees impersonating another
-- employee by changing that name. Admin renames must update assignments separately.
create or replace function private.guard_employee_profile()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  if auth.role() = 'authenticated' and not private.is_admin() and (new.name is distinct from old.name or new.day_rate is distinct from old.day_rate) then
    raise exception 'Only administrators can change employee names or day rates';
  end if;
  return new;
end $$;
drop trigger if exists guard_employee_profile on public.profiles;
create trigger guard_employee_profile before update on public.profiles
for each row execute function private.guard_employee_profile();

create or replace function private.guard_employee_lead()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  if auth.role() = 'authenticated' and not private.is_admin() and (
    new.assigned_to is distinct from old.assigned_to or
    new.value is distinct from old.value or new.deposit is distinct from old.deposit or
    new.deposit_paid is distinct from old.deposit_paid or new.balance is distinct from old.balance
  ) then raise exception 'Only administrators can reassign jobs or change job finances'; end if;
  return new;
end $$;
drop trigger if exists guard_employee_lead on public.leads;
create trigger guard_employee_lead before update on public.leads
for each row execute function private.guard_employee_lead();

-- Contact directory and financial ledger are office-only. Employee timesheets
-- retain their existing self/admin policies.
do $$ declare table_name text; begin
  foreach table_name in array array['contacts'] loop
    execute format('drop policy if exists organisation_select on public.%I', table_name);
    execute format('drop policy if exists organisation_insert on public.%I', table_name);
    execute format('drop policy if exists organisation_update on public.%I', table_name);
    execute format('create policy organisation_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin())', table_name);
    execute format('create policy organisation_insert on public.%I for insert to authenticated with check (organisation_id = private.current_organisation_id() and private.is_admin())', table_name);
    execute format('create policy organisation_update on public.%I for update to authenticated using (organisation_id = private.current_organisation_id() and private.is_admin()) with check (organisation_id = private.current_organisation_id() and private.is_admin())', table_name);
  end loop;
  foreach table_name in array array['payment_runs', 'worker_payments'] loop
    execute format('drop policy if exists finance_select on public.%I', table_name);
    execute format('create policy finance_select on public.%I for select to authenticated using (organisation_id = private.current_organisation_id() and (private.is_admin() or user_id = any(private.current_worker_ids())))', table_name);
  end loop;
end $$;
drop policy if exists profile_select on public.profiles;
create policy profile_select on public.profiles for select to authenticated
  using (organisation_id = private.current_organisation_id() and (private.is_admin() or id = auth.uid()));

-- Assigned task lists stay private to their owners and administrators.
drop policy if exists organisation_select on public.general_tasks;
drop policy if exists organisation_insert on public.general_tasks;
drop policy if exists organisation_update on public.general_tasks;
create policy organisation_select on public.general_tasks for select to authenticated
  using (organisation_id = private.current_organisation_id() and (private.is_admin() or assigned_to ?| private.current_worker_ids()));
create policy organisation_insert on public.general_tasks for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and (private.is_admin() or assigned_to = to_jsonb(array[auth.uid()::text])));
create policy organisation_update on public.general_tasks for update to authenticated
  using (organisation_id = private.current_organisation_id() and (private.is_admin() or assigned_to = to_jsonb(array[auth.uid()::text])))
  with check (organisation_id = private.current_organisation_id() and (private.is_admin() or assigned_to = to_jsonb(array[auth.uid()::text])));

-- Quotes are financial documents. Surveys follow the underlying job assignment.
drop policy if exists quotes_org_access on public.quotes;
create policy quotes_org_access on public.quotes for all to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin())
  with check (organisation_id = private.current_organisation_id() and private.is_admin());
drop policy if exists roof_surveys_org_access on public.roof_surveys;
create policy roof_surveys_org_access on public.roof_surveys for all to authenticated
  using (organisation_id = private.current_organisation_id() and exists (select 1 from public.leads l where l.id = lead_id))
  with check (organisation_id = private.current_organisation_id() and exists (select 1 from public.leads l where l.id = lead_id));

-- Private object paths are organisation/leads/job-id/filename. Legacy paths
-- remain administrator-only until explicitly migrated.
create or replace function private.can_access_attachment(object_name text)
returns boolean language sql stable security definer set search_path = public
as $$ select split_part(object_name, '/', 1) = private.current_organisation_id()::text
  and (private.is_admin() or (split_part(object_name, '/', 2) = 'leads' and exists (
    select 1 from public.leads l where l.id = split_part(object_name, '/', 3)
      and l.organisation_id = private.current_organisation_id()
      and private.can_access_assigned_lead(l.assigned_to)))) $$;
revoke all on function private.can_access_attachment(text) from public;
grant execute on function private.can_access_attachment(text) to authenticated;
drop policy if exists attachment_select on storage.objects;
drop policy if exists attachment_insert on storage.objects;
drop policy if exists attachment_update on storage.objects;
drop policy if exists attachment_delete on storage.objects;
create policy attachment_select on storage.objects for select to authenticated
  using (bucket_id = 'crm-attachments' and private.can_access_attachment(name));
create policy attachment_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'crm-attachments' and private.can_access_attachment(name));
create policy attachment_update on storage.objects for update to authenticated
  using (bucket_id = 'crm-attachments' and private.can_access_attachment(name))
  with check (bucket_id = 'crm-attachments' and private.can_access_attachment(name));
create policy attachment_delete on storage.objects for delete to authenticated
  using (bucket_id = 'crm-attachments' and private.can_access_attachment(name) and private.is_admin());

alter table public.quotes enable row level security;
alter table public.roof_surveys enable row level security;

alter table public.organisations enable row level security;
revoke all on public.organisations from anon, authenticated;
grant select on public.organisations to authenticated;
drop policy if exists organisation_member_select on public.organisations;
create policy organisation_member_select on public.organisations for select to authenticated using(id=private.current_organisation_id());

-- Preserve the existing website enquiry route with insert-only public access.
-- No public reads, arbitrary job states, reassignment or financial writes.
create or replace function public.crm_insert_organisation_id()
returns uuid language sql stable security definer set search_path=public
as $$ select case when auth.role()='anon' then '00000000-0000-0000-0000-000000000001'::uuid else private.current_organisation_id() end $$;
revoke all on function public.crm_insert_organisation_id() from public;
grant execute on function public.crm_insert_organisation_id() to anon, authenticated;
alter table public.leads alter column organisation_id set default public.crm_insert_organisation_id();

create or replace function private.normalise_website_enquiry()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  if auth.role()='anon' then
    if jsonb_typeof(new.notes)='string' then
      new.notes=jsonb_build_array(jsonb_build_object('id',gen_random_uuid()::text,'content',new.notes #>> '{}','author','Website','date',now()::text));
    end if;
    new.job_ref='WEB-' || upper(left(replace(new.id,'-',''),12));
  end if;
  return new;
end $$;
drop trigger if exists normalise_website_enquiry on public.leads;
create trigger normalise_website_enquiry before insert on public.leads for each row execute function private.normalise_website_enquiry();
drop policy if exists "Allow website inserts" on public.leads;
drop policy if exists website_enquiry_insert on public.leads;
create policy website_enquiry_insert on public.leads for insert to anon with check (
  organisation_id='00000000-0000-0000-0000-000000000001'::uuid and stage='New Lead' and source='Website'
  and value=0 and deposit=0 and balance=0 and deposit_paid=false and assigned_to=''
  and length(trim(name)) between 1 and 100 and (length(phone)>0 or length(email)>0)
  and tasks='[]'::jsonb and files='[]'::jsonb and photos='[]'::jsonb and materials='[]'::jsonb
  and jsonb_typeof(notes)='array' and jsonb_array_length(notes)<=1
  and survey_date is null and start_date is null and end_date is null and completed_date is null and paid_date is null
);
grant insert (id,name,phone,email,address,job_type,stage,source,notes,created_at,updated_at) on public.leads to anon;

select set_config('proline.admin_id',(select id::text from public.profiles where active and role='admin' limit 1),true);
select set_config('proline.worker_id',(select id::text from public.profiles where active and role='worker' order by id limit 1),true);
select set_config('proline.other_id',(select id::text from public.profiles where active and role='worker' and id::text<>current_setting('proline.worker_id') order by id limit 1),true);
select set_config('proline.fixture_a','release-test-'||gen_random_uuid()::text,true);
select set_config('proline.fixture_b','release-test-'||gen_random_uuid()::text,true);
insert into public.leads(id,name,assigned_to,organisation_id) select current_setting('proline.fixture_a'),'Isolated release check A',name,organisation_id from public.profiles where id::text=current_setting('proline.worker_id');
insert into public.leads(id,name,assigned_to,organisation_id) select current_setting('proline.fixture_b'),'Isolated release check B',name,organisation_id from public.profiles where id::text=current_setting('proline.other_id');
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('proline.worker_id'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare n integer; begin
  select count(*) into n from public.leads where id=current_setting('proline.fixture_a');
  if n<>1 then raise exception 'Worker cannot see assigned test job'; end if;
  select count(*) into n from public.leads where id=current_setting('proline.fixture_b');
  if n<>0 then raise exception 'Worker can see another employee test job'; end if;
  select count(*) into n from public.profiles where id::text<>current_setting('proline.worker_id');
  if n<>0 then raise exception 'Worker can read coworker payroll profiles'; end if;
  update public.leads set phone='07000000000' where id=current_setting('proline.fixture_a');
  get diagnostics n=row_count;
  if n<>1 then raise exception 'Worker cannot update own assigned test job'; end if;
  begin
    update public.leads set value=999 where id=current_setting('proline.fixture_a');
    raise exception using errcode='ZX001',message='Worker changed job finances';
  exception when insufficient_privilege or raise_exception then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('proline.admin_id'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare n integer; begin
  select count(*) into n from public.leads where id in(current_setting('proline.fixture_a'),current_setting('proline.fixture_b'));
  if n<>2 then raise exception 'Admin cannot see both isolated test jobs'; end if;
  update public.leads set stage='Quote Sent',updated_at='2026-11-01T12:00:00Z' where id=current_setting('proline.fixture_a');
  update public.leads set phone='07000000001',updated_at='2026-11-01T12:01:00Z' where id=current_setting('proline.fixture_a') and updated_at='2026-11-01T12:00:00Z';
  get diagnostics n=row_count;
  if n<>1 then raise exception 'Version-guarded update failed'; end if;
  update public.leads set phone='07000000002' where id=current_setting('proline.fixture_a') and updated_at='2026-11-01T12:00:00Z';
  get diagnostics n=row_count;
  if n<>0 then raise exception 'Stale version overwrote a newer edit'; end if;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
do $$ begin
  begin
    perform id from public.leads limit 1;
    raise exception using errcode='ZX002',message='Anonymous caller read customer records';
  exception when insufficient_privilege then null; end;
end $$;
insert into public.leads(id,name,phone,address,job_type,stage,source,notes,created_at,updated_at)
values('release-website-'||gen_random_uuid()::text,'Isolated website check','07000000000','TA1 1AA','Roof Repair','New Lead','Website',to_jsonb('Release test only'::text),now()::text,now()::text);
reset role;
select 'PASS: assigned staff isolation, admin access, financial protection, stale-write protection, anonymous read denial and website enquiry insert. ALL CHANGES ROLLED BACK.' as release_validation;
rollback;
