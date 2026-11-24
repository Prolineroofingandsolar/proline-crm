-- Durable new-lead notification outbox. The opaque dispatch id grants no CRM
-- read or write access and can only claim its corresponding queued event.
begin;
create table if not exists private.lead_push_outbox (
  id uuid primary key default gen_random_uuid(),
  lead_id text not null references public.leads(id) on delete cascade,
  organisation_id uuid not null references public.organisations(id) on delete cascade,
  state text not null default 'pending' check (state in ('pending','processing','sent','failed')),
  attempts integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  lease_until timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (lead_id)
);
create table if not exists private.lead_push_deliveries (
  event_id uuid not null references private.lead_push_outbox(id) on delete cascade,
  device_id uuid not null references public.native_push_devices(id) on delete cascade,
  delivered_at timestamptz,
  primary key (event_id, device_id)
);
revoke all on private.lead_push_outbox, private.lead_push_deliveries from public, anon, authenticated;

create or replace function private.enqueue_lead_push() returns trigger
language plpgsql security definer set search_path = '' as $$
declare event_id uuid; project_url text; anon_key text;
begin
  -- Native CRM inserts already send their own alerts. This path handles the
  -- public website specifically until all clients use the common outbox.
  if auth.uid() is not null or lower(trim(coalesce(new.source, ''))) <> 'website' then return new; end if;
  insert into private.lead_push_outbox (lead_id, organisation_id)
    values (new.id, new.organisation_id) on conflict (lead_id) do nothing returning id into event_id;
  if event_id is not null then
    select decrypted_secret into project_url from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1;
    select decrypted_secret into anon_key from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' limit 1;
    if project_url is not null and anon_key is not null then
      begin
        perform net.http_post(url := project_url || '/functions/v1/lead-push-dispatch',
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || anon_key),
          body := jsonb_build_object('event_id', event_id));
      exception when others then
        raise warning 'Lead push dispatch request failed: %', sqlerrm;
      end;
    end if;
  end if;
  return new;
exception when others then
  -- Lead submission takes precedence over a notification; failures are logged.
  raise warning 'Could not enqueue lead push: %', sqlerrm;
  return new;
end $$;
revoke all on function private.enqueue_lead_push() from public, anon, authenticated;
drop trigger if exists on_lead_inserted on public.leads;
create trigger on_lead_inserted after insert on public.leads for each row execute function private.enqueue_lead_push();

-- Only the trusted edge function uses these narrowly-scoped RPCs.
create or replace function public.claim_lead_push(p_event_id uuid)
returns table(event_id uuid, organisation_id uuid, lead_id text, lead_name text, job_type text, attempt integer)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with claimed as (
    update private.lead_push_outbox o
    set state = 'processing', attempts = o.attempts + 1, lease_until = now() + interval '2 minutes'
    where o.id = p_event_id and o.attempts < 12 and o.next_attempt_at <= now()
      and (o.state in ('pending','failed') or (o.state = 'processing' and o.lease_until < now()))
    returning o.id, o.organisation_id, o.lead_id, o.attempts
  )
  select c.id, c.organisation_id, l.id, l.name, l.job_type, c.attempts from claimed c
    join public.leads l on l.id = c.lead_id and l.organisation_id = c.organisation_id;
end $$;
revoke all on function public.claim_lead_push(uuid) from public, anon, authenticated;
grant execute on function public.claim_lead_push(uuid) to service_role;

create or replace function public.finish_lead_push(p_event_id uuid, p_attempt integer, p_success boolean, p_error text default null)
returns void language sql security definer set search_path = '' as $$
  update private.lead_push_outbox set state = case when p_success then 'sent' else 'failed' end,
    last_error = left(p_error, 500), lease_until = null,
    next_attempt_at = now() + interval '5 minutes'
  where id = p_event_id and state = 'processing' and attempts = p_attempt;
$$;
revoke all on function public.finish_lead_push(uuid, integer, boolean, text) from public, anon, authenticated;
grant execute on function public.finish_lead_push(uuid, integer, boolean, text) to service_role;

create or replace function public.lead_push_devices(p_event_id uuid)
returns table(device_id uuid, device_token text, environment text, bundle_id text)
language sql security definer set search_path = '' as $$
  select d.id, d.device_token, d.environment, d.bundle_id
  from private.lead_push_outbox o
  join public.native_push_devices d on d.organisation_id = o.organisation_id and d.active
  join public.profiles p on p.id = d.user_id and p.organisation_id = o.organisation_id and p.active and p.role = 'admin'
  left join private.lead_push_deliveries receipt on receipt.event_id = o.id and receipt.device_id = d.id
  where o.id = p_event_id and o.state = 'processing' and receipt.delivered_at is null;
$$;
revoke all on function public.lead_push_devices(uuid) from public, anon, authenticated;
grant execute on function public.lead_push_devices(uuid) to service_role;

create or replace function public.mark_lead_push_delivered(p_event_id uuid, p_device_id uuid, p_attempt integer)
returns void language sql security definer set search_path = '' as $$
  insert into private.lead_push_deliveries(event_id, device_id, delivered_at)
  select o.id, d.id, now() from private.lead_push_outbox o
  join public.native_push_devices d on d.id = p_device_id and d.organisation_id = o.organisation_id
  join public.profiles p on p.id = d.user_id and p.organisation_id = o.organisation_id and p.active and p.role = 'admin'
  where o.id = p_event_id and o.state = 'processing' and o.attempts = p_attempt
  on conflict (event_id,device_id) do update set delivered_at = excluded.delivered_at;
$$;
revoke all on function public.mark_lead_push_delivered(uuid,uuid,integer) from public, anon, authenticated;
grant execute on function public.mark_lead_push_delivered(uuid,uuid,integer) to service_role;

create or replace function public.lead_push_delivery_count(p_event_id uuid)
returns bigint language sql security definer set search_path = '' as $$
  select count(*) from private.lead_push_deliveries where event_id = p_event_id and delivered_at is not null;
$$;
revoke all on function public.lead_push_delivery_count(uuid) from public, anon, authenticated;
grant execute on function public.lead_push_delivery_count(uuid) to service_role;

create or replace function private.retry_lead_pushes()
returns void language plpgsql security definer set search_path = '' as $$
declare item record; project_url text; anon_key text;
begin
  select decrypted_secret into project_url from vault.decrypted_secrets where name = 'SUPABASE_URL' limit 1;
  select decrypted_secret into anon_key from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' limit 1;
  if project_url is null or anon_key is null then raise warning 'Lead push retry credentials missing'; return; end if;
  for item in select id from private.lead_push_outbox
    where attempts < 12 and next_attempt_at <= now()
      and (state in ('pending','failed') or (state = 'processing' and lease_until < now()))
    order by created_at limit 100
  loop
    perform net.http_post(url := project_url || '/functions/v1/lead-push-dispatch',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' || anon_key),
      body := jsonb_build_object('event_id', item.id));
  end loop;
end $$;
revoke all on function private.retry_lead_pushes() from public, anon, authenticated;
select cron.schedule('proline-lead-push-retry', '* * * * *', 'select private.retry_lead_pushes()');
commit;
