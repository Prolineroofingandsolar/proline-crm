# Supabase authentication and RLS migration

The native apps currently use the existing CRM `users` table and compare a client-side SHA-256 password hash. This keeps compatibility with the live web app, but it is not a safe production authentication design: the anonymous client must be able to read password hashes and the database cannot reliably identify the signed-in user for row-level security (RLS).

Do not switch the native client independently. Migrate the web app, native apps, and database together using the staged plan below.

## Target design

- Supabase Auth owns passwords and sessions. No application table stores `password_hash`.
- A `profiles` table maps `auth.users.id` to display name, role, active status, and organisation.
- Every business table has an `organisation_id` column.
- RLS is enabled on `leads`, `contacts`, `general_tasks`, `timesheet_entries`, storage objects, and any future customer-data table.
- Policies authorize rows through active organisation membership. Manager-only writes use a role check in the database, not a hidden client control.
- Files and photos are stored in private Supabase Storage buckets; database rows store object paths rather than public URLs.

## Safe rollout

1. Back up the database and test in a separate Supabase project.
2. Create Auth accounts for active staff and a `profiles` row keyed by each Auth UUID. Never copy existing password hashes into Supabase Auth; issue password-reset/invite links.
3. Add nullable `organisation_id` and owner Auth UUID columns to business tables, backfill them, verify every row, and only then make them non-null.
4. Add membership helper functions and RLS policies. Test manager, salesperson, inactive-user, and cross-organisation access with Supabase's SQL policy tests.
5. Update web and Apple clients to sign in with Supabase Auth, persist the Supabase session in Keychain, and fetch the signed-in profile. Remove the legacy user-table password query.
6. Move file/photo handling to a private Storage bucket with signed URLs and matching storage-object RLS policies.
7. Release all clients, monitor authorization failures, then revoke anonymous access to password data and remove `password_hash` after the rollback window.

## Required policy behaviours

- Active members can read rows belonging to their organisation.
- Salespeople can update rows they own or are assigned, according to company rules.
- Managers/admins can manage all rows in their organisation.
- No user can read or mutate another organisation's rows.
- Timesheets belong to the submitting user; only managers can approve them.
- Storage paths begin with the organisation UUID and policies verify that prefix.

## Acceptance checks

- An anonymous request cannot select any customer or password data.
- A signed-in user cannot access another organisation even by guessing an ID.
- Disabling a profile immediately blocks CRM access.
- Password reset, session refresh, sign-out, account invite, and revoked-session flows work on macOS, iOS, and the web app.
- A private file URL expires and cannot be opened without an authorised session.

Keep the current compatibility login only until this coordinated migration is complete.
