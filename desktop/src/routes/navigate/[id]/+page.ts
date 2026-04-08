import { fetchBuildingById, fetchSpaces, getSpaceGlbUrl } from '$lib/supabase'
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

  return {
    buildingName: building.name ?? 'Building',
    spaces: spaceEntries,
  }
}
