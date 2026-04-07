import { createClient } from '@supabase/supabase-js'
import type { Anchor, Building, BuildingSpace, Position, RigidTransform, Space } from './types'

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL as string,
  import.meta.env.VITE_SUPABASE_KEY as string
)

export async function fetchSpaces(): Promise<Space[]> {
  const { data, error } = await supabase
    .from('spaces')
    .select('*')
    .order('name', { ascending: true })
  if (error) throw error
  return data as Space[]
}

export function getSpaceGlbUrl(glbPath: string): string {
  const { data } = supabase.storage
    .from('spaces_bucket')
    .getPublicUrl(glbPath)
  return data.publicUrl
}

export async function fetchAnchors(spaceId: string | null = null): Promise<Anchor[]> {
  let query = supabase.from('anchors').select('*').order('created_at', { ascending: false })
  if (spaceId) query = query.eq('space_id', spaceId)
  const { data, error } = await query
  if (error) throw error
  return data as Anchor[]
}

export async function insertAnchor({ name, glbPosition, spaceId }: { name: string; glbPosition: Position; spaceId: string }): Promise<Anchor> {
  const { data, error } = await supabase
    .from('anchors')
    .insert({
      name: name || 'Unnamed',
      glb_position: glbPosition,
      space_id: spaceId,
    })
    .select()
    .single()
  if (error) throw error
  return data as Anchor
}

export async function setGlbPosition(id: string, glbPosition: Position): Promise<void> {
  const { error } = await supabase
    .from('anchors')
    .update({ glb_position: glbPosition })
    .eq('id', id)
  if (error) throw error
}

export async function deleteAnchor(id: string): Promise<void> {
  const { error } = await supabase.from('anchors').delete().eq('id', id)
  if (error) throw error
}

export async function upsertCentroidAnchor(spaceId: string, glbPosition: Position): Promise<void> {
  // Delete any existing centroid anchor for this space, then insert fresh.
  await supabase.from('anchors').delete().eq('space_id', spaceId).eq('name', '__centroid__')
  const { error } = await supabase.from('anchors').insert({
    name: '__centroid__',
    glb_position: glbPosition,
    space_id: spaceId,
    is_reference: false,
  })
  if (error) throw error
}

export async function fetchUserPosition(userId: string): Promise<Position | null> {
  const { data, error } = await supabase
    .from('users')
    .select('glb_position')
    .eq('id', userId)
    .single()
  if (error) throw error
  return (data?.glb_position as Position) ?? null
}

export async function fetchBuildingById(id: string): Promise<Building & { building_spaces: BuildingSpace[] }> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, building_spaces(*)')
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Building & { building_spaces: BuildingSpace[] }
}

export async function fetchCompletedBuildings(): Promise<(Building & { building_spaces: BuildingSpace[] })[]> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, building_spaces(*)')
    .eq('draft', false)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as (Building & { building_spaces: BuildingSpace[] })[]
}

export async function fetchDraftBuildings(): Promise<(Building & { building_spaces: BuildingSpace[] })[]> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, building_spaces(*)')
    .eq('draft', true)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as (Building & { building_spaces: BuildingSpace[] })[]
}

// Creates a draft building with all spaces pre-inserted (transforms null until stitched).
export async function createDraftBuilding(
  name: string,
  orderedSpaceIds: string[]
): Promise<string> {
  const { data: building, error: buildingErr } = await supabase
    .from('buildings')
    .insert({ name, draft: true })
    .select('id')
    .single()
  if (buildingErr) throw buildingErr

  const rows = orderedSpaceIds.map((spaceId, index) => ({
    building_id: building.id,
    space_id: spaceId,
    index,
    offset_transformation: null,
  }))

  const { error } = await supabase.from('building_spaces').insert(rows)
  if (error) throw error

  return building.id
}

export async function updateBuildingSpaceTransform(
  buildingId: string,
  spaceId: string,
  transform: RigidTransform
): Promise<void> {
  const { error } = await supabase
    .from('building_spaces')
    .update({ offset_transformation: transform })
    .eq('building_id', buildingId)
    .eq('space_id', spaceId)
  if (error) throw error
}

export async function finalizeDraftBuilding(buildingId: string): Promise<void> {
  const { error } = await supabase
    .from('buildings')
    .update({ draft: false })
    .eq('id', buildingId)
  if (error) throw error
}

export async function deleteBuilding(buildingId: string): Promise<void> {
  const { error } = await supabase.from('buildings').delete().eq('id', buildingId)
  if (error) throw error
}

export function subscribeUserPosition(
  userId: string,
  onChange: (pos: Position | null) => void
): () => void {
  const channel = supabase
    .channel(`user-pos-${userId}`)
    .on(
      'postgres_changes',
      { event: 'UPDATE', schema: 'public', table: 'users', filter: `id=eq.${userId}` },
      (payload) => onChange((payload.new as { glb_position?: Position }).glb_position ?? null)
    )
    .subscribe()
  return () => supabase.removeChannel(channel)
}
