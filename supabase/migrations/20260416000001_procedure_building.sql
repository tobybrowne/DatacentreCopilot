-- Associate procedures with a building so localisation can use the same
-- request_navigation flow as nav mode.
ALTER TABLE procedures
  ADD COLUMN building_id UUID REFERENCES buildings(id) ON DELETE SET NULL;
