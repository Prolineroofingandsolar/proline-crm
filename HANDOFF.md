# Handoff notes

Newest first. Add an entry when you finish a piece of work so the next person or agent (Codex, Claude) knows what changed.

## 11 November 2026 — staff accounts, deployed and released (Claude)

**Start here.** `main` is at `7a4db41`. The long-running divergence between
`origin/main` and the Codex line is resolved: `main` was fast-forwarded to the
merge, so there is one line of history again. PR #17 closed itself as merged.
The merge itself is described in the entry below this one — read it, because
it lists two clashes that only surfaced when compiling.

### Live right now

- **Web:** `https://proline-crm.pages.dev` rebuilt from `main`. Confirmed by
  downloading the live bundle and finding "Give app access", "Set new
  password", "Payroll only" and "Removed access" in it. Cloudflare's asset
  hash does not match a local `npm run build`; that appears to be a builder
  difference, not a content problem, but it was verified by feature rather
  than by matching bytes.
- **Supabase:** `worker-invite` deployed three times today. Deployed source
  was diffed against the repository before each deploy and matched.
- **Mac:** `/Applications/ProLine CRM.app` replaced with a Release build,
  0.2.0 (3), signed Apple Development. The previous 0.1.0 (1) from September
  is backed up at `~/Applications-ProLineCRM-backup-20261111-185103`.
- **iPhone:** installed directly to Will's connected device with
  `xcrun devicectl`, 0.2.0 (3). **Development-signed, so it expires in about
  a week** and will stop opening. TestFlight is still the lasting answer.

### What changed in staff accounts

1. **Re-adding someone whose access was removed** failed with Auth's raw
   "already been registered". Removal is a soft deactivate, so the answer is
   almost always Restore. Both the invitation and add-a-login paths now look
   the person up first and say so by name. The invitation path previously did
   not check at all and would mint a code that could never be accepted.
2. **`set_staff_password`** — an administrator can set a new password for
   anyone in their organisation, including another administrator. Refuses
   payroll-only staff, refuses self (Settings does that), 8–72 characters
   because bcrypt ignores anything past 72 bytes.
3. **`enable_staff_login`** — turns a payroll-only person into a real user.
   They already have an auth row with a placeholder address, so this renames
   that login instead of creating a second record. **The profile write has to
   happen in the function:** `sync_staff_auth_email` only updates profiles
   "where email is not null", so it deliberately skips payroll-only rows. If
   the profile write does not land on exactly one row the placeholder address
   is restored.
4. **`SupabaseHTTPError`** no longer prefixes the server's message with
   "The server returned HTTP 409:".

All three actions were verified against the live backend with disposable
organisations, including the employee actually signing in afterwards, and the
15 live acceptance checks pass.

### Open, and needing Will

- **Self-service password reset does not work end to end.** Email delivery
  itself works (a real reset reached his inbox). Three settings block the
  rest, none of them code:
  - Site URL points at the marketing website, so emailed links land there.
    Should be `https://proline-crm.pages.dev`.
  - The CRM may not be in the redirect allow-list. If it is not, Supabase
    ignores what the web app asks for. This could not be tested from outside:
    `/auth/v1/recover` returns 200 for any `redirect_to`.
  - The reset email template probably has no `{{ .Token }}`, which means
    **recovery on iPhone and Mac cannot work at all**, since those use a typed
    code rather than a link.
  Reading the project auth config needs a management token, and that was
  blocked as credential access. Not worked around.
- Delivery was only proven to the project owner's own address. Supabase's
  built-in email reaches team members regardless, so it does **not** prove a
  worker would receive one. Test with a real staff address.
- **The merge has never had a human read.** It is live for staff now.
  `DashboardView.swift` and `SettingsView.swift` are where two designs were
  combined by hand. Revert target if needed: `fab2f51`.

### Watch out

- Resolving a conflict with `git checkout --ours <file>` takes that side's
  whole file and silently discards everything the other side added outside the
  markers. It deleted PR #14's `fetchTimesheetJobOptions` before the merge was
  redone by editing markers in place. Resolve in place.
- `xcodegen generate` writes `apple/project.yml` into the Xcode project.
  Opening the project in Xcode rewrites the macOS scheme and that churn gets
  swept into commits by a blanket `git add`. Regenerate rather than hand-edit.
- `supabase db push` is still unsafe; the migration history is still out of
  sync. Nothing was pushed today.


## 11 November 2026 — merge of the Codex line into main (Claude)

**What this was.** `origin/main` and the Codex line had diverged: `origin/main`
carried PRs #10–#15 (staff permissions, roofing tools, web/Mac pipeline parity,
mobile Simple mode), and the Codex line carried the job team, the redesigned
native job screen, staff contact email and the Grok bot panel. Neither side was
uniformly newer. This merge brings them together on
`claude/merge-origin-main-20261110`.

18 files conflicted, 49 hunks. How they were settled:

- **Ours:** `SupabaseService.swift`, `LeadDetailView.swift` (the redesigned job
  screen — checked that it keeps Delete Lead, Book survey, Schedule job and
  Voice update), `worker-invite`, `operations-assistant`,
  `build-grok-connector.mjs`, `eslint.config.js`, `App.tsx`, `Sidebar.tsx`,
  `BottomNav.tsx`, `docs/employee-release-status.md`.
- **Theirs:** `useStore.ts` (Simple mode opens on Jobs, PR #14) and the
  `LoginView` staff-login toggle.
- **Merged by hand, keeping both:** `StaffManager.tsx` and `SettingsView.swift`
  (origin/main's wording plus our contact email), and `DashboardView.swift`,
  where origin/main's Mac metric cards and Today's schedule were kept *and* the
  Grok bot panel added, instead of letting the redesign drop them.
- **Regenerated:** `project.pbxproj` and the schemes, via `xcodegen generate`.
  Do not hand-merge those; `apple/project.yml` is the source of truth.

**Two clashes git could not see**, both caught by compiling:

1. Duplicate `fetchLead(id:)` in `SupabaseService.swift` — each side had one in a
   different place, so the text merge kept both. Ours was kept (it loads job
   teams).
2. `Color(nsColor: .windowBackgroundColor)` and a `.navigationTitle` from
   origin/main were spliced into `assistantInput`, which iOS also compiles.
   `macDashboard` already had them; the duplicates were removed.

**Watch out.** Resolving a conflict with `git checkout --ours <file>` takes that
side's *whole* file and silently discards everything the other side added outside
the markers. It deleted PR #14's `fetchTimesheetJobOptions` here before the merge
was redone by editing the markers in place. Resolve in place.

**Confirm this.** `loginEnabled` now defaults to `true`, so a new staff member
gets an app login by default; the Codex line had `false`. One word in
`LoginView.swift` if that is wrong.

**Verified.** macOS and iOS builds, 59/59 native tests, production web build,
65/65 Node tests, clean lint, and the web app loading without console errors.
Not verified: a signed-in walkthrough of this final tree, and anything about
Apple distribution, which this merge does not change.

## 1–2 November 2026 — PR #14 (Claude)

**Before you start:** Will's local clone at `~/proline-crm` had about 83 uncommitted changed files on `main` (in-progress Codex work) when this was merged. Commit or stash those before `git pull`, then pull `main` (now at `ee32bce` or later). PR #14 touched `src/App.tsx`, `src/components/Layout/BottomNav.tsx`, `src/components/Layout/Sidebar.tsx`, `src/store/useStore.ts`, `src/pages/TimesheetPage.tsx` and four files in `apple/Shared/`, so expect conflicts there.

A clean worktree used for the iOS build is at `~/proline-crm-main-ee32bce`. Remove it with `git -C ~/proline-crm worktree remove ~/proline-crm-main-ee32bce` when no longer needed.

### What changed

1. **Staff no longer see the Pipeline on web.** Pipeline is admin-only in the sidebar, bottom nav and `ADMIN_ONLY_PAGES` in `src/App.tsx`. Non-admins who land on an admin page are sent to Jobs. Staff bottom nav is Jobs, Timesheet, Tasks, Calendar (Roofing tools under More). Admin Simple mode now opens on Jobs. The iPhone/Mac apps already hid Pipeline from workers.
2. **Workers can log time against any active job.** Previously the worker timesheet job list only showed jobs whose `leads.assigned_to` exactly matched the worker's name (enforced by RLS `private.can_access_assigned_lead`), so it was usually empty and a crew couldn't share a job. Will chose: show every active job by name and reference only, keep full job details assigned-only.
   - New migration `supabase/migrations/2026110103_timesheet_job_options.sql` adds `public.timesheet_job_options()` (security definer). It returns `id, name, job_ref, stage` for Won / Scheduled / In Progress / Completed jobs in the caller's organisation. Authenticated users only.
   - iPhone/Mac: `AppState.timesheetJobOptions`, `timesheetJobs` and `timesheetJobLabel(_:)`, plus `SupabaseService.fetchTimesheetJobOptions()` and the `TimesheetJobOption` model. Used by `WorkerDayEntrySheet` in `TimesheetViews.swift`. A failed fetch is ignored, and the app then falls back to assigned jobs.
   - Web: `TimesheetPage.tsx` calls `supabase.rpc('timesheet_job_options')` and merges the result with `leads`.

### Deployed

- **Database:** the migration above was applied to production (`qzvdzzvkocmulcfujyea`) with `supabase db query --linked -f`. It was **not** recorded in the migration history table.
- **Web:** Cloudflare Pages deployed `main` automatically.
- **iPhone:** 0.2.0 build 3 was uploaded to App Store Connect for internal TestFlight. Before that, the iOS build was clean and the native tests passed 59/59.

### Watch out

- **Do not run `supabase db push`.** The remote migration history is out of sync: 2026083103, 2026102701, 2026103001, 2026110101, 2026110102 and 2026110103 show as not applied, even though at least 2026110103 is live. A push would try to re-run them. Apply single files with `supabase db query --linked -f <file>` until the history is repaired (`supabase migration repair`). Also check whether 2026110101 (company details) and 2026110102 (staff identity) are actually live.
- Job assignment is still by display name, with one assignee per job. See `docs/employee-release-status.md`.
- Next iOS upload needs build 4 or higher.
