# Notes for coding agents

Before starting work, read:

- `HANDOFF.md`: what the last session changed, what was deployed, and open warnings. Add your own entry at the top when you finish.
- `docs/employee-release-status.md`: release state and repeatable checks.

Ground rules:

- Run `npm run check:release` (build, Node tests, lint) before pushing web changes.
- Do not run `supabase db push`. The remote migration history is out of sync (see `HANDOFF.md`). Apply single migrations with `supabase db query --linked -f <file>`.
- Admins see everything. Every other role (user, worker, labourer, casual) is staff and must not see Pipeline, Leads, Dashboard, Contacts, Files, Reports, CIS, Banking, Virtual Office or Settings. Keep web (`src/App.tsx`, `src/components/Layout/`) and native (`apple/Shared/Views/RootView.swift`) in step.
