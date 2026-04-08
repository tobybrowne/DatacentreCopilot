import { fetchSpaces, getSpaceGlbUrl } from '$lib/supabase'
import { error } from '@sveltejs/kit'
import type { PageLoad } from './$types'

export const load: PageLoad = async ({ params }) => {
  const spaces = await fetchSpaces()
  const space = spaces.find(s => s.id === params.id)
  if (!space || !space.glb_path) throw error(404, 'Space not found')

  return {
    buildingName: space.name ?? 'Space',
    spaces: [{ url: getSpaceGlbUrl(space.glb_path), transform: null }],
  }
}
