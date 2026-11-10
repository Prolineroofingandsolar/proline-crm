-- Keep the CRM profile and the Auth login address in the same transaction.
-- A payroll-only profile has no login email and is intentionally left alone.
begin;
create or replace function public.sync_staff_auth_email()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email, username = new.email
      where id = new.id and email is not null;
  end if;
  return new;
end $$;
revoke all on function public.sync_staff_auth_email() from public, anon, authenticated;
drop trigger if exists sync_staff_auth_email on auth.users;
create trigger sync_staff_auth_email after update of email on auth.users
  for each row execute function public.sync_staff_auth_email();
create or replace function public.staff_email_sync_ready() returns boolean
language sql security definer set search_path = '' as $$
  select exists (select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'auth.users'::regclass and t.tgname = 'sync_staff_auth_email'
      and not t.tgisinternal and t.tgenabled in ('O', 'A'))
$$;
revoke all on function public.staff_email_sync_ready() from public, anon, authenticated;
grant execute on function public.staff_email_sync_ready() to service_role;

-- Legacy lead assignments contain names. Rename them and the profile in one
-- transaction, rejecting ambiguous names rather than moving another person's work.
create or replace function public.update_staff_details_safe(p_org uuid, p_id uuid, p_name text, p_role text, p_rate numeric, p_cis integer)
returns void language plpgsql security definer set search_path = '' as $$
declare old_name text; new_name text := btrim(p_name);
begin
  if new_name is null or length(new_name) < 1 or length(new_name) > 120
    or p_role not in ('admin', 'worker', 'labourer')
    or (p_rate is not null and (p_rate < 0 or p_rate > 10000))
    or p_cis not in (20, 30) then
    raise exception 'Invalid staff details';
  end if;
  lock table public.profiles, public.leads in share row exclusive mode;
  select name into old_name from public.profiles where id = p_id and organisation_id = p_org for update;
  if not found then raise exception 'Employee not found in your organisation'; end if;
  if new_name is distinct from old_name then
    if exists (select 1 from public.profiles where organisation_id = p_org and id <> p_id
       and lower(btrim(name)) in (lower(btrim(old_name)), lower(new_name))) then
      raise exception 'This name is shared by another staff member; assignments need manual review';
    end if;
    if lower(btrim(old_name)) <> lower(new_name) and exists (
      select 1 from public.leads where organisation_id = p_org and lower(btrim(assigned_to)) = lower(new_name)
    ) then
      raise exception 'Jobs are already assigned to the new name; assignments need manual review';
    end if;
    update public.leads set assigned_to = new_name,
      updated_at = to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      where organisation_id = p_org and lower(btrim(assigned_to)) = lower(btrim(old_name));
  end if;
  update public.profiles set name = new_name, role = p_role, day_rate = p_rate, cis_rate = p_cis
    where id = p_id and organisation_id = p_org;
end $$;
revoke all on function public.update_staff_details_safe(uuid, uuid, text, text, numeric, integer) from public, anon, authenticated;
grant execute on function public.update_staff_details_safe(uuid, uuid, text, text, numeric, integer) to service_role;

create or replace function public.update_staff_pay_safe(p_org uuid, p_id uuid, p_expected jsonb, p_details jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare affected integer;
begin
  update public.profiles set utr_number = p_details->>'utr_number', bank_name = p_details->>'bank_name',
    bank_account_number = p_details->>'bank_account_number', bank_sort_code = p_details->>'bank_sort_code'
  where id = p_id and organisation_id = p_org
    and utr_number is not distinct from p_expected->>'utr_number'
    and bank_name is not distinct from p_expected->>'bank_name'
    and bank_account_number is not distinct from p_expected->>'bank_account_number'
    and bank_sort_code is not distinct from p_expected->>'bank_sort_code';
  get diagnostics affected = row_count;
  return affected = 1;
end $$;
revoke all on function public.update_staff_pay_safe(uuid, uuid, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.update_staff_pay_safe(uuid, uuid, jsonb, jsonb) to service_role;
commit;
