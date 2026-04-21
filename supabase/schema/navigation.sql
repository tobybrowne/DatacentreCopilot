-- Navigation subsystem
-- Routes define a path between two anchors via an ordered list of waypoints in building-space coords.
-- Used by the AR navigation system to guide users through a building.

CREATE TABLE routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_anchor_id UUID NOT NULL REFERENCES anchors(id) ON DELETE CASCADE,
  end_anchor_id UUID NOT NULL REFERENCES anchors(id) ON DELETE CASCADE,
  waypoints JSONB NOT NULL -- ordered array of {x, y, z} points in building coordinate frame
);
