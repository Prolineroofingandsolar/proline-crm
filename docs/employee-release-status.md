# Employee release status — 1 November 2026

Release preparation is in progress. Do not treat an uploaded Apple build as an installed employee release.

## Implemented and verified

- Conflict-safe web job saving, same-record retry protection and retained unsaved drafts. Independent edits merge; conflicting edits require review. Quote Sent uses the same guarded save route.
- Rebuilt web and native Staff & access screens: searchable directory, roles, rates, invitations, cancellation, removal and restoration. History is preserved. Server checks restrict management to active administrators in the same company.
- Removed legacy unauthenticated web sign-in. Active Supabase profiles and organisation-scoped row-level permissions now protect production records. Employees cannot change their wages, job assignments or financial fields.
- Applied production security cutover after a successful rollback-only dry run. Preserved the public website enquiry insert route without granting public customer reads. Deployed worker-invite with its existing own-token verification architecture.
- Company contact details now save to shared server settings. Only administrators can change them.
- Production web build, full lint and 45 isolated Node tests passed. Xcode GUI macOS build and 59 native tests passed before the final company-settings addition; final native rebuild remains required.
- All 14 live acceptance checks passed with isolated temporary accounts and records. Covered admin/employee sign-in, company settings, assigned job visibility, payroll protection, anonymous access denial, guarded status changes, staff management, deactivation of existing sessions, restoration, invitation single use and cancellation, payroll-only staff and session refresh. Cleanup passed; existing customer records were untouched.

## Distribution

- Existing web host: https://proline-crm.pages.dev — Cloudflare Pages builds repository main. Verify the new deployment after publication; the older live version is not evidence that the new frontend shipped.
- iPhone: native scheme ProLineCRM-iOS, bundle com.prolineroofingandsolar.crm.native. Xcode verified upload of 0.2.0 (2) to App Store Connect on 1 November. This upload used TestFlight Internal Only. Employees must not be granted App Store Connect access merely to install the CRM. Final build 0.2.0 (3) requires a regular App Store Connect upload and an appropriate TestFlight route, including Apple beta review if external testing is used.
- Mac: native scheme ProLineCRM-macOS, bundle com.prolineroofingandsolar.crm.native.mac. Final rebuild, signed distribution and installation verification remain outstanding. No employee installer or verified TestFlight invitation link exists yet.

## Remaining verification

Complete final Apple build and distribution; verify the new public web deployment. Physical iPhone layout, cross-device realtime behaviour, interrupted uploads, password recovery email delivery, push notifications, durable offline use and real Grok session refresh after expiry are not yet verified end to end. In-memory draft retention is not durable offline storage. Invitations generate codes for administrators to share; they do not send emails automatically. Legacy employee assignment uses names, so employee renaming needs a stable assignment-ID migration before it is a routine safe operation.

## Repeatable checks

Run `npm run check:release` for production web compilation, 45 Node tests and full lint. Run `NODE_USE_ENV_PROXY=1 DO_NOT_TRACK=1 node scripts/release/live-acceptance.mjs` with the existing authenticated Supabase CLI to exercise temporary live accounts; the script cleans up only its own fixtures. Use Xcode for native tests and signed archives: command-line account/keychain and simulator access differs from the verified GUI environment.
