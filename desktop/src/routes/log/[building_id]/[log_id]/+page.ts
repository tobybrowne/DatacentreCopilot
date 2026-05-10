import { fetchLogById, fetchBuildingById, getSpaceGlbUrl } from '$lib/supabase'
import type { PageLoad } from './$types'
import type { RigidTransform } from '$lib/types'

export const load: PageLoad = async ({ params }) => {
  const [log, building] = await Promise.all([
    fetchLogById(params.log_id),
    fetchBuildingById(params.building_id),
  ])
  if (!log) throw new Error('Log not found')

  const spaces = await Promise.all(
    [...building.spaces]
      .filter(s => s.glb_path)
      .sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
      .map(async s => ({
        url: await getSpaceGlbUrl(s.glb_path!),
        transform: s.offset_transformation as RigidTransform | null,
        boundingBox: s.bounding_box,
      }))
  )

  return { log, spaces, buildingId: params.building_id }
}
