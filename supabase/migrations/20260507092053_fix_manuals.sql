ALTER TABLE assets DROP COLUMN model_id;
ALTER TABLE assets ADD COLUMN asset_model_id uuid REFERENCES asset_models(id) ON DELETE SET NULL;

ALTER TABLE asset_models ADD COLUMN manual_id uuid REFERENCES manuals(id) ON DELETE SET NULL;