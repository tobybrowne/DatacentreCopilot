import { fetchBuildingById, fetchSpaces, getSpaceGlbUrl, getNavMeshUrl, supabase } from '$lib/supabase'
import type { PageLoad } from './$types'
import type { RigidTransform } from '$lib/types'

export const load: PageLoad = async ({ params }) => {
  const [building, spaces] = await Promise.all([
    fetchBuildingById(params.id),
    fetchSpaces(),
  ])

  const spaceEntries = [...building.building_spaces]
    .sort((a, b) => a.index - b.index)
    .filter(bs => {
      const space = spaces.find(s => s.id === bs.space_id)
      return space?.glb_path
    })
    .map(bs => {
      const space = spaces.find(s => s.id === bs.space_id)!
      return {
        url: getSpaceGlbUrl(space.glb_path!),
        transform: bs.offset_transformation as RigidTransform | null,
      }
    })

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
