# ProLine CRM connector for the Stace pilot

ProLine exposes an organisation-scoped Model Context Protocol (MCP) API that Grok Bot can use as a custom connector. During the pilot, business data is read-only. An optional check-in tool may write only to the AI run log; it cannot change jobs, tasks, customers, schedules or finances.

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

The four business tools are read-only. If pilot check-ins are enabled, `proline_agent_checkin` can record up to eight short findings in the Virtual Office. It cannot change CRM operational records, record payments, send messages, purchase materials or access another organisation.

Internal task and proposal tools are implemented behind `PROLINE_AGENT_WRITES_ENABLED=false`. Leave that switch off throughout the five-day pilot.

## Useful first prompts

- "Use ProLine CRM to plan my day. Show the evidence for each priority."
- "Summarise my pipeline by stage and flag the biggest outstanding balances."
- "Find the job for Taylor and tell me its current stage and open tasks."

## Health check

```text
https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/health
```

See `GROK_STACE_PILOT.md` for the exact Bot description, one-time test and routine instructions.
