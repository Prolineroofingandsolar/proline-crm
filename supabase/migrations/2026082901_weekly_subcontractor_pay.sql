begin;

-- Some early installations created the finance tables outside migrations, after
-- the organisation foundation had run. Bring those tables up to the current
-- tenant-aware shape before installing the narrower worker/admin policies.
alter table public.payment_runs add column if not exists organisation_id uuid references public.organisations(id);
update public.payment_runs
set organisation_id = '00000000-0000-0000-0000-000000000001'::uuid
where organisation_id is null;
alter table public.payment_runs alter column organisation_id set default private.current_organisation_id();
alter table public.payment_runs alter column organisation_id set not null;

alter table public.worker_payments add column if not exists organisation_id uuid references public.organisations(id);
update public.worker_payments
set organisation_id = '00000000-0000-0000-0000-000000000001'::uuid
where organisation_id is null;
alter table public.worker_payments alter column organisation_id set default private.current_organisation_id();
alter table public.worker_payments alter column organisation_id set not null;

drop policy if exists finance_select on public.payment_runs;
drop policy if exists finance_manage on public.payment_runs;
drop policy if exists payment_run_select on public.payment_runs;
drop policy if exists payment_run_worker_insert on public.payment_runs;
drop policy if exists payment_run_worker_update on public.payment_runs;
drop policy if exists payment_run_admin_manage on public.payment_runs;
create policy payment_run_select on public.payment_runs for select to authenticated
  using (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
create policy payment_run_worker_insert on public.payment_runs for insert to authenticated
  with check (organisation_id = private.current_organisation_id() and user_id = auth.uid()::text and status = 'submitted');
create policy payment_run_worker_update on public.payment_runs for update to authenticated
  using (organisation_id = private.current_organisation_id() and user_id = auth.uid()::text and status in ('due', 'submitted'))
  with check (organisation_id = private.current_organisation_id() and user_id = auth.uid()::text and status = 'submitted');
create policy payment_run_admin_manage on public.payment_runs for all to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin())
  with check (organisation_id = private.current_organisation_id() and private.is_admin());

drop policy if exists finance_select on public.worker_payments;
drop policy if exists finance_manage on public.worker_payments;
drop policy if exists worker_payment_select on public.worker_payments;
drop policy if exists worker_payment_admin_manage on public.worker_payments;
create policy worker_payment_select on public.worker_payments for select to authenticated
  using (organisation_id = private.current_organisation_id() and (user_id = any(private.current_worker_ids()) or private.is_admin()));
create policy worker_payment_admin_manage on public.worker_payments for all to authenticated
  using (organisation_id = private.current_organisation_id() and private.is_admin())
  with check (organisation_id = private.current_organisation_id() and private.is_admin());

commit;
