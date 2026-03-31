export interface Position {
  x: number
  y: number
  z: number
}

export interface RigidTransform {
  position: Position
  quaternion: { x: number; y: number; z: number; w: number }
}

export interface Building {
  id: string
  name: string | null
}

export interface Space {
  id: string
  name: string
  glb_path: string | null
}

export interface Anchor {
  id: string
  name: string | null
  glb_position: Position | null
  is_reference: boolean
  ml2_id: string | null
  space_id: string | null
  created_at: string
}
