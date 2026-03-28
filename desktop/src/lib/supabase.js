import { createClient } from "@supabase/supabase-js";

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_KEY
);

export async function fetchAnchors() {
  const { data, error } = await supabase
    .from("anchors")
    .select("*")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function insertAnchor({ name, glbPosition }) {
  const { data, error } = await supabase
    .from("anchors")
    .insert({
      name: name || "Unnamed",
      glb_position: glbPosition,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function setGlbPosition(id, glbPosition) {
  const { error } = await supabase
    .from("anchors")
    .update({ glb_position: glbPosition })
    .eq("id", id);
  if (error) throw error;
}

export async function deleteAnchor(id) {
  const { error } = await supabase.from("anchors").delete().eq("id", id);
  if (error) throw error;
}

export async function fetchUserPosition(userId) {
  const { data, error } = await supabase
    .from("users")
    .select("glb_position")
    .eq("id", userId)
    .single();
  if (error) throw error;
  return data?.glb_position ?? null;
}

export function subscribeUserPosition(userId, onChange) {
  const channel = supabase
    .channel(`user-pos-${userId}`)
    .on(
      "postgres_changes",
      { event: "UPDATE", schema: "public", table: "users", filter: `id=eq.${userId}` },
      (payload) => onChange(payload.new.glb_position ?? null)
    )
    .subscribe();
  return () => supabase.removeChannel(channel);
}
