-- Workers can log time against any active job, not only the one assigned to them.
-- This exposes job name and reference only. Full job details (address, phone,
-- prices, notes) stay behind the existing assigned-job row-level security.
begin;
create or replace function public.timesheet_job_options()
returns table (id text, name text, job_ref text, stage text)
language sql stable security definer set search_path = public
as $$
  select l.id::text, l.name, l.job_ref, l.stage
  from public.leads l
  where private.current_organisation_id() is not null
    and l.organisation_id = private.current_organisation_id()
    and l.stage in ('Won', 'Scheduled', 'In Progress', 'Completed')
  order by l.name
$$;
revoke all on function public.timesheet_job_options() from public, anon;
grant execute on function public.timesheet_job_options() to authenticated;
commit;
