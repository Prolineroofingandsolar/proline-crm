alter table public.monzo_receipts enable row level security;
revoke all on public.monzo_receipts from anon, authenticated;
grant select, insert, update, delete on public.monzo_receipts to authenticated;
create policy monzo_receipts_proline_admin on public.monzo_receipts for all to authenticated
  using (private.current_organisation_id() = '00000000-0000-0000-0000-000000000001'::uuid and private.is_admin())
  with check (private.current_organisation_id() = '00000000-0000-0000-0000-000000000001'::uuid and private.is_admin());
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;
grant select, insert, update, delete on public.push_tokens to authenticated;
create policy push_tokens_own on public.push_tokens for all to authenticated
  using (user_id = any(private.current_worker_ids()))
  with check (user_id = any(private.current_worker_ids()));
