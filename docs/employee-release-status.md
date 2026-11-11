# Employee release status — 11 November 2026

The 1 November record is kept below, unchanged. This section supersedes its
Distribution and Remaining verification notes.

## Where things actually are

- **Web:** live from `main` at `7a4db41` on https://proline-crm.pages.dev.
  Verified by downloading the live bundle and finding today's features in it.
- **Supabase:** `worker-invite` deployed from `7a4db41`. Deployed source was
  diffed against the repository and matched. No migrations were applied and
  `supabase db push` was not run.
- **Mac:** Release build 0.2.0 (3) installed at `/Applications/ProLine CRM.app`,
  signed Apple Development, launches and signs in. The September 0.1.0 (1) that
  was there before had no staff management in it at all, which is why staff
  could not be removed on the Mac. Backup at
  `~/Applications-ProLineCRM-backup-20261111-185103`.
- **iPhone:** 0.2.0 (3) installed directly to the connected device.
  Development-signed, so it stops opening after about a week.

Neither Apple build is distributable to employees. Mac Developer ID export is
still blocked on the certificate problem recorded below, and TestFlight is
still pending beta review. Both installs are for this machine and this phone.

## Still to do

- Self-service password reset needs three Supabase settings changed: Site URL,
  the redirect allow-list, and `{{ .Token }}` in the reset email template.
  Email delivery itself is proven, but only to the project owner's address.
  See HANDOFF.md for detail.
- The merge that produced this release has not had a human read, and is live
  for staff. Revert target `fab2f51`.
- An administrator can reset another administrator's password, and can change
  their sign-in email. Admins are assumed to trust each other.

# Employee release status — 1 November 2026

Release preparation is in progress. Do not treat an uploaded Apple build as an installed employee release.

## Implemented and verified

- Conflict-safe web job saving, same-record retry protection and retained unsaved drafts. Independent edits merge; conflicting edits require review. Quote Sent uses the same guarded save route.
- Rebuilt web and native Staff & access screens: searchable directory, roles, rates, invitations, cancellation, removal and restoration. History is preserved. Server checks restrict management to active administrators in the same company.
- Removed legacy unauthenticated web sign-in. Active Supabase profiles and organisation-scoped row-level permissions now protect production records. Employees cannot change their wages, job assignments or financial fields.
- Applied production security cutover after a successful rollback-only dry run. Preserved the public website enquiry insert route without granting public customer reads. Deployed worker-invite with its existing own-token verification architecture.
- Company contact details now save to shared server settings. Only administrators can change them.
- Production web build, full lint and 45 isolated Node tests passed. Xcode GUI macOS build and 59 native tests passed before the final company-settings addition; final source also compiled in Xcode Cloud for both iOS and macOS. Mac export failed at signing, not compilation.
- All 15 live acceptance checks passed with isolated temporary accounts and records. Covered admin/employee sign-in, company settings, assigned job visibility, payroll protection, anonymous access denial, guarded status changes, staff management, deactivation of existing sessions, restoration, invitation single use and cancellation, payroll-only staff and session refresh. The deployed Grok MCP connector also accepts active admins, rejects employees, and remains accessible after a session refresh. Cleanup passed; existing customer records were untouched.

## Distribution

- **Web live:** https://proline-crm.pages.dev. Commit 570b039a76b0c86cb54b6475d9c12fd258c76650 passed both Cloudflare Pages and Workers Builds. The old Workers mirror https://proline-crm.royal-art-964b.workers.dev had failed because its catch-all `_redirects` rule looped; the rule was removed and explicit Workers SPA assets configuration added. Production compilation and Wrangler deployment dry-run passed. Pages retains dashboard configuration and its native SPA fallback.
- **iPhone:** native scheme ProLineCRM-iOS, bundle com.prolineroofingandsolar.crm.native. Internal build 0.2.0 (2) uploaded and reached Testing. Xcode Cloud build 28 compiled and signed the final native source; its external TestFlight action is verified **Pending Beta Review**. The saved Default workflow now uses App Store Connect distribution and the existing External Testers group. There is no verified employee installation link yet. Existing internal testers may use their existing TestFlight invitation; do not grant employees App Store Connect team access merely to install.
- **Mac:** native scheme ProLineCRM-macOS, bundle com.prolineroofingandsolar.crm.native.mac. App Groups were enabled for the Mac app and widget. Cloud build 32 produced an App Store artifact but failed Developer ID export: Apple reports an existing or pending managed certificate and no matching private key. No certificates were revoked. The Mac employee release workflow now prepares an App Store Connect build without the notarization step; build 33 was queued. Its success and TestFlight delivery have not yet been verified.
- **Mac local installation:** cloud development build 0.2.0 (29) downloaded from App Store Connect and passed deep signature validation. Finder replacement initially verified at /Applications, but after the launch attempt the bundle was absent. Cause is not established; do not describe that update as successfully running. Restored the original build 1 from `apple/build/BeforeEmployeeRelease-20261101/ProLine CRM.app`, verified matching executable SHA-256 and valid signature, and verified its sign-in window opens. Customer records and app data were not deleted. The restored app is not the completed employee release.
- **Mac shared container:** the existing group.com.prolineroofingandsolar.crm was enabled for both the Mac app and its widget with the owner's approval.

### Employees using the web release

Open https://proline-crm.pages.dev in Safari, Chrome or another supported browser. An administrator opens Settings → Staff & access → Add staff → Create invitation, then privately shares the generated code. Employees select “Have an invitation?” on the web sign-in screen, join with that code and choose their own password. Invitations are manually shared, not emailed automatically. Existing secure employee accounts can sign in normally. Native employee installation remains pending the Apple gates above.

## Remaining verification

Complete Apple beta review and verify Mac build 33 and employee distribution. The original Mac app has been restored; its recurring-save fix is not installed. Xcode app controls repeatedly time out and command-line native builds crash in this sandbox. Physical iPhone layout, cross-device realtime behaviour, interrupted uploads, password recovery email delivery, push notifications, durable offline use and real Grok session refresh after expiry are not yet verified end to end. In-memory draft retention is not durable offline storage. Invitations generate codes for administrators to share; they do not send emails automatically. Legacy employee assignment uses names, so employee renaming needs a stable assignment-ID migration before it is a routine safe operation.

## Repeatable checks

Run `npm run check:release` for production web compilation, 45 Node tests and full lint. Run `NODE_USE_ENV_PROXY=1 DO_NOT_TRACK=1 node scripts/release/live-acceptance.mjs` with the existing authenticated Supabase CLI to exercise temporary live accounts; the script cleans up only its own fixtures. Use Xcode for native tests and signed archives: command-line account/keychain and simulator access differs from the verified GUI environment.
