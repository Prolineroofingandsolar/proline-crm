# ProLine CRM connector for the Stace pilot

ProLine exposes an organisation-scoped Model Context Protocol (MCP) API that Grok Bot can use as a custom connector. Reads are organisation-scoped. Narrow write tools can manage evidence-backed internal notes and tasks, verified shortlisted leads and approval proposals; they cannot contact customers, change live schedules, move money, purchase, delete or change job ownership, dates or stages.

## Connector URL

```text
https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/mcp
```

## Connect it to Grok Bot

1. First check whether the signed-in account already includes Grok Bot. Do not enable extra usage or API billing.
2. Open Grok Bot and go to **Connect apps**.
3. Choose **New connector** and then **Custom**.
4. Name it **ProLine CRM** and paste the connector URL above.
5. Complete the ProLine sign-in flow with an active administrator account.
6. Ask Stace to run `proline_status` and confirm the returned organisation before using any other tool.

The Supabase Auth OAuth server must be enabled for the project before the sign-in flow can complete. If Grok reports that the OAuth server is disabled, enable the OAuth server in the Supabase Auth settings and retry the connection.

## Available tools

- `proline_status` verifies the connected ProLine organisation and access level.
- `proline_daily_plan` ranks operational issues from live jobs and tasks.
- `proline_pipeline_summary` totals jobs, values and balances by pipeline stage without returning customer contact details.
- `proline_find_jobs` finds live jobs by customer name, job reference or job type.

The four business tools are read-only. `proline_check_for_changes` prevents unchanged data from waking a full review. `proline_agent_checkin` records up to eight short findings in the Virtual Office. Controlled internal actions require an active staged agent and evidence, and every change is audited.

Internal action tools are behind `PROLINE_AGENT_WRITES_ENABLED`. Enabling it does not enable customer contact, schedule changes, payments, purchases, deletions or job-stage changes; those capabilities do not exist in this connector.

## Useful first prompts

- "Use ProLine CRM to plan my day. Show the evidence for each priority."
- "Summarise my pipeline by stage and flag the biggest outstanding balances."
- "Find the job for Taylor and tell me its current stage and open tasks."

## Health check

```text
https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/health
```

See `GROK_STACE_PILOT.md` for the exact Bot description, one-time test and routine instructions.
