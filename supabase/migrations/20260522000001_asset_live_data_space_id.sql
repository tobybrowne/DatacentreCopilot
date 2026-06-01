ALTER TABLE asset_live_data ADD COLUMN space_id uuid REFERENCES spaces(id) ON DELETE SET NULL;

DROP VIEW IF EXISTS latest_asset_live_data;

CREATE VIEW latest_asset_live_data AS
SELECT DISTINCT ON (asset_id)
    id, asset_id, space_id, data, alarm, timestamp, created_at, updated_at
FROM asset_live_data
ORDER BY asset_id, timestamp DESC;
