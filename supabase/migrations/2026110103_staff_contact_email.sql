-- Store a contact address separately from the authentication email.
-- Existing accounts and staff history are not changed.
alter table public.profiles add column if not exists contact_email text;
