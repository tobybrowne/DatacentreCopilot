import { writable } from 'svelte/store'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'

export const session = writable<Session | null>(null)

// Initialise from existing session and keep in sync
supabase.auth.getSession().then(({ data }) => session.set(data.session))
supabase.auth.onAuthStateChange((_event, s) => session.set(s))

export async function signIn(email: string, password: string): Promise<string | null> {
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  return error?.message ?? null
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut()
}
