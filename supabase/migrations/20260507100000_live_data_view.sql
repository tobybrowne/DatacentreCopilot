-- PostgREST (the Supabase HTTP layer) does not expose DISTINCT ON, so we
-- can't do "latest row per asset" in a single query from the client.
-- This view wraps the DISTINCT ON so GDScript can query it like a plain table.
CREATE INDEX IF NOT EXISTS idx_asset_live_data_asset_ts
    ON asset_live_data (asset_id, timestamp DESC);

CREATE OR REPLACE VIEW latest_asset_live_data AS
SELECT DISTINCT ON (asset_id)
    id, asset_id, data, alarm, timestamp, created_at, updated_at
FROM asset_live_data
ORDER BY asset_id, timestamp DESC;
