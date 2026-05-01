export interface Position {
  x: number;
  y: number;
  z: number;
}

export interface RigidTransform {
  position: Position;
  quaternion: { x: number; y: number; z: number; w: number };
}

export interface Building {
  id: string;
  name: string | null;
  draft: boolean;
}

export interface Space {
  id: string;
  name: string;
  glb_path: string | null;
  building_id: string | null;
  building_index: number | null;
  offset_transformation: RigidTransform | null;
}

export interface Anchor {
  id: string;
  name: string | null;
  glb_position: Position | null;
  anchor_type: string;
  ml2_id: string | null;
  space_id: string | null;
  created_at: string;
}

export interface Asset {
  id: string;
  name: string | null;
  asset_type: string | null;
  anchor_id: string | null;
  building_id: string;
  created_at: string;
  updated_at: string;
}

export interface AssetWithAnchor extends Asset {
  anchor: Anchor | null;
}
