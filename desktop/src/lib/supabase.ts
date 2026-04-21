import { createClient } from '@supabase/supabase-js'
import type { Anchor, Building, Position, RigidTransform, Space } from './types'

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

export function getNavMeshUrl(navMeshPath: string): string {
  const { data } = supabase.storage
    .from('spaces_bucket')
    .getPublicUrl(navMeshPath)
  return data.publicUrl
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

export async function fetchBuildingById(id: string): Promise<Building & { spaces: Space[] }> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, spaces(*)')
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Building & { spaces: Space[] }
}

export async function fetchCompletedBuildings(): Promise<(Building & { spaces: Space[] })[]> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, spaces(*)')
    .eq('draft', false)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as (Building & { spaces: Space[] })[]
}

export async function fetchDraftBuildings(): Promise<(Building & { spaces: Space[] })[]> {
  const { data, error } = await supabase
    .from('buildings')
    .select('*, spaces(*)')
    .eq('draft', true)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as (Building & { spaces: Space[] })[]
}

// Creates a draft building and assigns spaces to it in order.
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

  await Promise.all(orderedSpaceIds.map((spaceId, index) =>
    supabase
      .from('spaces')
      .update({ building_id: building.id, building_index: index, offset_transformation: null })
      .eq('id', spaceId)
  ))

  return building.id
}

export async function updateBuildingSpaceTransform(
  _buildingId: string,
  spaceId: string,
  transform: RigidTransform
): Promise<void> {
  const { error } = await supabase
    .from('spaces')
    .update({ offset_transformation: transform })
    .eq('id', spaceId)
  if (error) throw error
}

export async function finalizeDraftBuilding(buildingId: string): Promise<void> {
  const { error } = await supabase
    .from('buildings')
    .update({ draft: false })
    .eq('id', buildingId)
  if (error) throw error
}

export async function saveNavMesh(
  buildingId: string,
  data: Uint8Array,
  buildSettings: Record<string, unknown>
): Promise<void> {
  const path = `navmeshes/${buildingId}.bin`

  const { error: uploadError } = await supabase.storage
    .from('spaces_bucket')
    .upload(path, data, { upsert: true, contentType: 'application/octet-stream' })
  if (uploadError) throw uploadError

  const { data: building, error: buildingError } = await supabase
    .from('buildings')
    .select('navmesh_id')
    .eq('id', buildingId)
    .single()
  if (buildingError) throw buildingError

  if (building.navmesh_id) {
    const { error } = await supabase
      .from('navmeshes')
      .update({ navmesh_path: path, build_settings: buildSettings, updated_at: new Date().toISOString() })
      .eq('id', building.navmesh_id)
    if (error) throw error
  } else {
    const { data: navmesh, error: insertError } = await supabase
      .from('navmeshes')
      .insert({ navmesh_path: path, build_settings: buildSettings })
      .select('id')
      .single()
    if (insertError) throw insertError

    const { error: updateError } = await supabase
      .from('buildings')
      .update({ navmesh_id: navmesh.id })
      .eq('id', buildingId)
    if (updateError) throw updateError
  }
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
