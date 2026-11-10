-- Single-use broker requests: only the service role can consume a nonce.
create table if not exists public.proline_grok_broker_nonces (
  nonce uuid primary key,
  created_at timestamptz not null default now()
);
alter table public.proline_grok_broker_nonces enable row level security;
revoke all on public.proline_grok_broker_nonces from public, anon, authenticated;

create or replace function public.proline_consume_grok_broker_nonce(request_nonce uuid)
returns boolean language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  delete from public.proline_grok_broker_nonces where created_at < now() - interval '5 minutes';
  insert into public.proline_grok_broker_nonces(nonce) values (request_nonce) on conflict do nothing;
  return found;
end;
$$;
revoke all on function public.proline_consume_grok_broker_nonce(uuid) from public, anon, authenticated;
grant execute on function public.proline_consume_grok_broker_nonce(uuid) to service_role;
