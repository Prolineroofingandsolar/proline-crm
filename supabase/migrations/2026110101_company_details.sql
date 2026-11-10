begin;
alter table public.organisations add column if not exists phone text not null default '';
alter table public.organisations add column if not exists email text not null default '';
alter table public.organisations add column if not exists address text not null default '';
alter table public.organisations add column if not exists vat text not null default '';
grant update(name,phone,email,address,vat) on public.organisations to authenticated;
drop policy if exists organisation_admin_update on public.organisations;
create policy organisation_admin_update on public.organisations for update to authenticated
  using(id=private.current_organisation_id() and private.is_admin())
  with check(id=private.current_organisation_id() and private.is_admin());
commit;
