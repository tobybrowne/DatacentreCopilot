CREATE TABLE asset_models (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    manufacturer TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

ALTER TABLE asset_models ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view asset models for sites they have access to"
ON asset_models FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = asset_models.site_id
  )
);
CREATE POLICY "Users can insert asset models for sites they have access to"
ON asset_models FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = asset_models.site_id
  )
);
CREATE POLICY "Users can update asset models for sites they have access to"
ON asset_models FOR UPDATE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = asset_models.site_id
  )
);
CREATE POLICY "Users can delete asset models for sites they have access to"
ON asset_models FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = asset_models.site_id
  )
);


CREATE TABLE manuals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    url TEXT, -- public URL
    path TEXT, -- path to supabase storage
    created_at TIMESTAMP DEFAULT NOW()
);

ALTER TABLE manuals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view manuals for sites they have access to"
ON manuals FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = manuals.site_id
  )
);
CREATE POLICY "Users can insert manuals for sites they have access to"
ON manuals FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = manuals.site_id
  )
);
CREATE POLICY "Users can update manuals for sites they have access to"
ON manuals FOR UPDATE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = manuals.site_id
  )
);
CREATE POLICY "Users can delete manuals for sites they have access to"
ON manuals FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM sites
    WHERE sites.id = manuals.site_id
  )
);

CREATE TABLE asset_manuals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_id UUID NOT NULL REFERENCES assets(id) ON DELETE CASCADE,
  manual_id UUID NOT NULL REFERENCES manuals(id) ON DELETE CASCADE
);

ALTER TABLE asset_manuals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view asset_manuals for assets and manuals they have access to"
ON asset_manuals FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM assets
    WHERE assets.id = asset_manuals.asset_id
  )
  AND EXISTS (
    SELECT 1
    FROM manuals
    WHERE manuals.id = asset_manuals.manual_id
  )
);
CREATE POLICY "Users can insert asset_manuals for assets and manuals they have access to"
ON asset_manuals FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM assets
    WHERE assets.id = asset_manuals.asset_id
  )
  AND EXISTS (
    SELECT 1
    FROM manuals
    WHERE manuals.id = asset_manuals.manual_id
  )
);
CREATE POLICY "Users can delete asset_manuals for assets and manuals they have access to"
ON asset_manuals FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM assets
    WHERE assets.id = asset_manuals.asset_id
  )
  AND EXISTS (
    SELECT 1
    FROM manuals
    WHERE manuals.id = asset_manuals.manual_id
  )
);

ALTER TABLE assets ADD COLUMN model_id UUID REFERENCES asset_models(id) ON DELETE SET NULL;