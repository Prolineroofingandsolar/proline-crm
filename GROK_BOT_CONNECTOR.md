# ProLine CRM connector for Grok Bot

ProLine exposes a read-only Model Context Protocol (MCP) API that Grok Bot can use as a custom connector.

## Connector URL

```text
https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/mcp
```

## Connect it to Grok Bot

1. Open Grok Bot and go to **Settings > Plugins**.
2. Choose **New connector** or **Custom MCP**.
3. Name it **ProLine CRM** and paste the connector URL above.
4. Complete the ProLine sign-in flow with an active administrator account.
5. Ask the Bot to run `proline_status` to verify the connection.

The Supabase Auth OAuth server must be enabled for the project before the sign-in flow can complete. If Grok reports that the OAuth server is disabled, enable the OAuth server in the Supabase Auth settings and retry the connection.

## Available tools

- `proline_status` verifies the connected ProLine organisation and access level.
- `proline_daily_plan` ranks operational issues from live jobs and tasks.
- `proline_pipeline_summary` totals jobs, values and balances by pipeline stage without returning customer contact details.
- `proline_find_jobs` finds live jobs by customer name, job reference or job type.

All tools are read-only. They cannot change CRM records, record payments, send messages, purchase materials or access another organisation.

## Useful first prompts

- "Use ProLine CRM to plan my day. Show the evidence for each priority."
- "Summarise my pipeline by stage and flag the biggest outstanding balances."
- "Find the job for Taylor and tell me its current stage and open tasks."

## Health check

```text
https://qzvdzzvkocmulcfujyea.supabase.co/functions/v1/proline-mcp/health
```
