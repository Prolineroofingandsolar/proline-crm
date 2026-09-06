# ProLine CRM staff security rollout

Do not apply `2026080902_enforce_rls.sql` or
`2026081601_roofing_workflows.sql` to production until every check below passes.
These migrations change who can read and write live customer, payroll and file
records.

## Known issues that must be corrected before deployment

1. `2026081601_roofing_workflows.sql` references
   `public.current_organisation_id()`, but the preceding migration creates
   `private.current_organisation_id()`. As written, a clean deployment will fail.
2. The `finance_select` policy in `2026080902_enforce_rls.sql` permits every
   authenticated member of the organisation to read every payment run and worker
   payment. It must restrict non-admin users to rows whose `user_id` matches their
   Auth UUID or linked `legacy_user_id`.
3. Native client filtering is useful for the interface, but it is not a database
   security boundary. The production RLS policies must be verified independently
   with both an admin token and an ordinary worker token.

## Read-only preflight

Run these queries in the Supabase SQL editor before any enforcement migration.
They do not modify data.

```sql
-- Every active non-casual legacy user must have one active Auth profile.
select
  u.id as legacy_user_id,
  u.name,
  u.username,
  u.role,
  p.id as auth_user_id,
  p.organisation_id,
  p.active
from public.app_users u
left join public.profiles p on p.legacy_user_id = u.id
where u.role <> 'casual'
order by u.name;

-- This must return zero rows before cutover.
select u.id, u.name, u.username, u.role
from public.app_users u
where u.role <> 'casual'
  and not exists (
    select 1
    from public.profiles p
    where p.legacy_user_id = u.id
      and p.active
  );

-- Every operational row needs an organisation before NOT NULL is enabled.
select 'leads' as table_name, count(*) as missing from public.leads where organisation_id is null
union all select 'contacts', count(*) from public.contacts where organisation_id is null
union all select 'general_tasks', count(*) from public.general_tasks where organisation_id is null
union all select 'timesheet_entries', count(*) from public.timesheet_entries where organisation_id is null
union all select 'payment_runs', count(*) from public.payment_runs where organisation_id is null
union all select 'worker_payments', count(*) from public.worker_payments where organisation_id is null;

-- Confirm there is exactly one active admin profile for the initial rollout.
select id, email, name, organisation_id
from public.profiles
where active and role = 'admin';
```

## Staged rollout

1. Take a Supabase database backup and record its restore point.
2. Correct the two migration defects above in a reviewed change.
3. Create and link every staff Auth account; do not share passwords.
4. Verify admin and ordinary-worker login on macOS and iPhone before RLS.
5. Apply the enforcement migration during a short maintenance window.
6. With an ordinary worker account, verify that another worker's payroll, bank
   details and timesheets cannot be read through the REST API.
7. Verify the admin can still create/edit leads, schedule jobs, approve pay runs,
   export accountant data and open private attachments.
8. Keep legacy login disabled only after every required staff account passes.

## Rollback trigger

Rollback immediately if an ordinary worker can read another worker's financial
records, if the admin loses access to live company data, or if any production row
becomes inaccessible because its organisation is missing or incorrect.
