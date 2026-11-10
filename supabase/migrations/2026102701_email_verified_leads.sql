-- Preserve source evidence and the existing active-Rodney and deduplication checks.
begin;
alter table public.ai_verified_lead_events drop constraint ai_verified_lead_events_source_check;
alter table public.ai_verified_lead_events add constraint ai_verified_lead_events_source_check check (source in ('website', 'mybuilder_shortlisted', 'email'));

CREATE OR REPLACE FUNCTION public.proline_create_verified_lead(target_organisation uuid, agent_slug text, lead_source text, source_event_id text, customer_name text, customer_phone text DEFAULT ''::text, customer_email text DEFAULT ''::text, customer_address text DEFAULT ''::text, requested_job_type text DEFAULT 'Roof Repair'::text, source_url text DEFAULT NULL::text, action_evidence text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_agent public.ai_agents%rowtype;
  existing_lead_id text;
  new_lead_id text := gen_random_uuid()::text;
  new_job_ref text := 'JOB-' || to_char(clock_timestamp() at time zone 'Europe/London', 'YYMMDD-HH24MISS-') || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
  safe_evidence text := trim(coalesce(action_evidence, ''));
  source_label text;
begin
  if lead_source not in ('website', 'mybuilder_shortlisted', 'email') then raise exception 'invalid verified lead source'; end if;
  if length(trim(coalesce(source_event_id, ''))) < 3 or length(source_event_id) > 180 then raise exception 'invalid source event'; end if;
  if length(trim(coalesce(customer_name, ''))) < 1 or length(customer_name) > 180 then raise exception 'invalid customer name'; end if;
  if length(trim(coalesce(requested_job_type, ''))) < 1 or length(requested_job_type) > 180 then raise exception 'invalid job type'; end if;
  if length(safe_evidence) < 5 or length(safe_evidence) > 1000 then raise exception 'verification evidence is required'; end if;
  if lead_source = 'mybuilder_shortlisted' and length(trim(coalesce(customer_phone, ''))) = 0 and length(trim(coalesce(customer_email, ''))) = 0 then
    raise exception 'MyBuilder contact details must have been shared before a CRM lead is created';
  end if;
  if lead_source = 'email' and position('@' in trim(coalesce(customer_email, ''))) < 2 then
    raise exception 'Email enquiries require the customer email address';
  end if;
  select * into target_agent from public.ai_agents
  where organisation_id = target_organisation and slug = 'rodney' and slug = agent_slug and active = true;
  if target_agent.id is null then raise exception 'active Rodney agent not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(target_organisation::text || ':' || lead_source || ':' || source_event_id, 0));
  select lead_id into existing_lead_id from public.ai_verified_lead_events
  where organisation_id = target_organisation and source = lead_source and ai_verified_lead_events.source_event_id = proline_create_verified_lead.source_event_id;
  if existing_lead_id is not null then
    return jsonb_build_object('lead_id', existing_lead_id, 'job_ref', (select job_ref from public.leads where id = existing_lead_id), 'duplicate', true);
  end if;

  source_label := case lead_source when 'website' then 'Website' when 'email' then 'Email' else 'MyBuilder' end;
  insert into public.leads (
    id, organisation_id, job_ref, name, phone, email, address, job_type, stage, value, deposit,
    deposit_paid, balance, source, assigned_to, progress, tasks, photos, notes, files, materials,
    mybuilder_url, created_at, updated_at
  ) values (
    new_lead_id, target_organisation, new_job_ref, trim(customer_name), trim(coalesce(customer_phone, '')),
    trim(coalesce(customer_email, '')), trim(coalesce(customer_address, '')), trim(requested_job_type),
    'New Lead', 0, 0, false, 0, source_label, '', 0, '[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'content', 'Verified ' || source_label || ' enquiry added by Rodney. Evidence: ' || safe_evidence, 'date', current_date::text, 'author', 'Rodney (AI)')),
    '[]'::jsonb, '[]'::jsonb, case when lead_source = 'mybuilder_shortlisted' then nullif(trim(coalesce(source_url, '')), '') else null end,
    now()::text, now()::text
  );
  insert into public.ai_verified_lead_events (organisation_id, agent_id, source, source_event_id, lead_id, evidence)
  values (target_organisation, target_agent.id, lead_source, trim(source_event_id), new_lead_id, safe_evidence);
  return jsonb_build_object('lead_id', new_lead_id, 'job_ref', new_job_ref, 'duplicate', false);
end;
$function$

commit;
