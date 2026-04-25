export const ssr = false
export const prerender = false

import { supabase } from '$lib/supabase'

export const load = async () => {
  // Restore session from localStorage before any child load functions run,
  // so the supabase client includes the auth token in storage requests.
  await supabase.auth.getSession()
  return {}
}
