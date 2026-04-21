-- Assets subsystem
-- Physical equipment tracked within a building.
-- Each asset optionally links to exactly one anchor (1-to-1 via UNIQUE constraint on anchor_id).

CREATE TYPE asset_type_enum AS ENUM (
  'humidifier', 'ats', 'ups', 'pdu', 'generator', 'sts', 'switchgear',
  'ahu', 'acch', 'crah', 'rpp', 'condensate_pump', 'duct_heater', 'heat_trace',
  'msb', 'transformer', 'exhaust_fan', 'vesda', 'breaker', 'switchboard',
  'dehumidifier', 'panelboard', 'pump', 'battery_string', 'fire_system', 'vfd',
  'fuel_tank', 'battery_charger', 'dry_cooler', 'heat_exchanger', 'cooling_tower',
  'mts', 'other'
);

CREATE TABLE assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT,
  asset_type asset_type_enum,
  anchor_id UUID UNIQUE REFERENCES anchors(id) ON DELETE SET NULL, -- UNIQUE enforces 1-to-1 with anchor
  building_id UUID NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- RLS: users can see/modify assets for buildings they have access to
ALTER TABLE assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view assets for buildings they have access to"
ON assets FOR SELECT USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = assets.building_id
  )
);
CREATE POLICY "Users can insert assets for buildings they have access to"
ON assets FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = assets.building_id
  )
);
CREATE POLICY "Users can delete assets for buildings they have access to"
ON assets FOR DELETE USING (
  EXISTS (
    SELECT 1
    FROM buildings
    WHERE buildings.id = assets.building_id
  )
);
