import { fetchBuildingById, fetchLogsForBuilding } from '$lib/supabase'
import type { PageLoad } from './$types'

export const load: PageLoad = async ({ params }) => {
  const [building, logs] = await Promise.all([
    fetchBuildingById(params.building_id),
    fetchLogsForBuilding(params.building_id),
  ])
  return { building, logs }
}
