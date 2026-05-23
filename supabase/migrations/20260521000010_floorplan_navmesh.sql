alter table buildings add column if not exists floorplan_id uuid references navmeshes(id);
