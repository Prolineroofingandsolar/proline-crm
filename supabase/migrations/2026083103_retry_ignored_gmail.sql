-- Retry messages that the earlier scanner marked as handled even when its AI
-- classification failed or was too strict.
delete from public.gmail_processed_messages where outcome = 'ignored';
