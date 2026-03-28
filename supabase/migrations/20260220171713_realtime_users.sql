-- Enable realtime for user position updates.
-- REPLICA IDENTITY FULL is required for filtered subscriptions (id=eq.x)
-- to work correctly — without it the old record isn't available for filtering.
ALTER TABLE users REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE users;
