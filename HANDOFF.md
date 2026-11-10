# Handoff notes

Newest first. Add an entry when you finish a piece of work so the next person or agent (Codex, Claude) knows what changed.

## 10 November 2026 — Ponytail plugin (Claude)

Installed the [Ponytail](https://github.com/DietrichGebert/ponytail) Claude Code plugin at project scope. `.claude/settings.json` now declares the `ponytail` marketplace and enables `ponytail@ponytail`, so Claude Code (local and cloud) offers to install it when the repo is trusted. It adds `/ponytail [lite|full|ultra|off]`, `/ponytail-review`, `/ponytail-audit`, `/ponytail-debt`, `/ponytail-gain`, `/ponytail-help`, plus three Node hooks (SessionStart, SubagentStart, UserPromptSubmit), so `node` must be on PATH. Its optional webhook is empty by default; nothing leaves the machine unless someone sets it with `/plugin configure ponytail@ponytail`. Remove both keys from `.claude/settings.json` to uninstall.

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
