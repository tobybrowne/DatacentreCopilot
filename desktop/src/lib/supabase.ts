import { createClient } from '@supabase/supabase-js'
import type { Anchor, Position, Space } from './types'

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

export async function insertAnchor({ name, glbPosition }: { name: string; glbPosition: Position }): Promise<Anchor> {
  const { data, error } = await supabase
    .from('anchors')
    .insert({
      name: name || 'Unnamed',
      glb_position: glbPosition,
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

export async function fetchUserPosition(userId: string): Promise<Position | null> {
  const { data, error } = await supabase
    .from('users')
    .select('glb_position')
    .eq('id', userId)
    .single()
  if (error) throw error
  return (data?.glb_position as Position) ?? null
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
