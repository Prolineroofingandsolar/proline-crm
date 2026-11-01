-- Narrow the previous organisation-wide employee access. No customer rows are changed.
-- Apply after the Auth/RLS cutover and verify with isolated admin/worker test accounts.
begin;
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
commit;
