import { fetchBuildingById, getSpaceGlbUrl, getNavMeshUrl, supabase } from '$lib/supabase'
import type { PageLoad } from './$types'
import type { RigidTransform } from '$lib/types'

export const load: PageLoad = async ({ params }) => {
  const [building] = await Promise.all([
    fetchBuildingById(params.id),
  ])

  const spaceEntries = [...building.spaces]
    .filter(s => s.glb_path)
    .sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
    .map(s => ({
      url: getSpaceGlbUrl(s.glb_path!),
      transform: s.offset_transformation as RigidTransform | null,
    }))

  let existingNavMesh: { url: string; buildSettings: Record<string, unknown> } | null = null
  if ((building as any).navmesh_id) {
    const { data: nm } = await supabase
      .from('navmeshes')
      .select('navmesh_path, build_settings')
      .eq('id', (building as any).navmesh_id)
      .single()
    if (nm?.navmesh_path) {
      existingNavMesh = {
        url: getNavMeshUrl(nm.navmesh_path),
        buildSettings: nm.build_settings ?? {},
      }
    }
  }

  return {
    buildingId: params.id,
    buildingName: building.name ?? 'Building',
    spaces: spaceEntries,
    existingNavMesh,
  }
}
