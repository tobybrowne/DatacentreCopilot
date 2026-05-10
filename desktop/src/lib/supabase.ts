import { createClient } from "@supabase/supabase-js";
import type {
  Anchor,
  Asset,
  AssetWithAnchor,
  Building,
  Position,
  RigidTransform,
  Space,
} from "./types";

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL as string,
  import.meta.env.VITE_SUPABASE_KEY as string
);

export async function fetchSpaces(): Promise<Space[]> {
  const { data, error } = await supabase
    .from("spaces")
    .select("*")
    .order("name", { ascending: true });
  if (error) throw error;
  return data as Space[];
}

export async function fetchSpaceById(id: string): Promise<Space> {
  const { data, error } = await supabase
    .from("spaces")
    .select("*")
    .eq("id", id)
    .single();
  if (error) throw error;
  return data as Space;
}

export async function getNavMeshUrl(navMeshPath: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from("spaces_bucket")
    .createSignedUrl(navMeshPath, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function getSpaceGlbUrl(glbPath: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from("spaces_bucket")
    .createSignedUrl(glbPath, 3600);
  if (error) throw error;
  return data.signedUrl;
}

export async function fetchAnchors(
  spaceId: string | null = null
): Promise<Anchor[]> {
  let query = supabase
    .from("anchors")
    .select("*")
    .order("created_at", { ascending: false });
  if (spaceId) query = query.eq("space_id", spaceId);
  const { data, error } = await query;
  if (error) throw error;
  return data as Anchor[];
}

export async function insertAnchor({
  name,
  glbPosition,
  spaceId,
  anchorType = "content",
}: {
  name: string;
  glbPosition: Position;
  spaceId: string;
  anchorType?: string;
}): Promise<Anchor> {
  const { data, error } = await supabase
    .from("anchors")
    .insert({
      name: name || "Unnamed",
      glb_position: glbPosition,
      space_id: spaceId,
      anchor_type: anchorType,
    })
    .select()
    .single();
  if (error) throw error;
  return data as Anchor;
}

export async function setGlbPosition(
  id: string,
  glbPosition: Position
): Promise<void> {
  const { error } = await supabase
    .from("anchors")
    .update({ glb_position: glbPosition })
    .eq("id", id);
  if (error) throw error;
}

export async function deleteAnchor(id: string): Promise<void> {
  const { error } = await supabase.from("anchors").delete().eq("id", id);
  if (error) throw error;
}

export async function unmapAnchor(id: string): Promise<void> {
  const { error } = await supabase
    .from("anchors")
    .update({ glb_position: null })
    .eq("id", id);
  if (error) throw error;
}


export async function fetchUserPosition(
  userId: string
): Promise<Position | null> {
  const { data, error } = await supabase
    .from("users")
    .select("glb_position")
    .eq("id", userId)
    .single();
  if (error) throw error;
  return (data?.glb_position as Position) ?? null;
}

export async function fetchBuildingById(
  id: string
): Promise<Building & { spaces: Space[] }> {
  const { data, error } = await supabase
    .from("buildings")
    .select("*, spaces(*)")
    .eq("id", id)
    .single();
  if (error) throw error;
  return data as Building & { spaces: Space[] };
}

export async function fetchCompletedBuildings(): Promise<
  (Building & { spaces: Space[] })[]
> {
  const { data, error } = await supabase
    .from("buildings")
    .select("*, spaces(*)")
    .eq("draft", false)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data as (Building & { spaces: Space[] })[];
}

export async function fetchDraftBuildings(): Promise<
  (Building & { spaces: Space[] })[]
> {
  const { data, error } = await supabase
    .from("buildings")
    .select("*, spaces(*)")
    .eq("draft", true)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data as (Building & { spaces: Space[] })[];
}

async function getUserSiteId(): Promise<string> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");
  const { data, error } = await supabase
    .from("users")
    .select("site_id")
    .eq("id", user.id)
    .single();
  if (error) throw error;
  if (!data.site_id) throw new Error("No site assigned to your account");
  return data.site_id;
}

// Creates a draft building and assigns spaces to it in order.
export async function createDraftBuilding(
  name: string,
  orderedSpaceIds: string[]
): Promise<string> {
  const site_id = await getUserSiteId();
  const { data: building, error: buildingErr } = await supabase
    .from("buildings")
    .insert({ name, draft: true, site_id })
    .select("id")
    .single();
  if (buildingErr) throw buildingErr;

  await Promise.all(
    orderedSpaceIds.map((spaceId, index) =>
      supabase
        .from("spaces")
        .update({
          building_id: building.id,
          building_index: index,
          offset_transformation: null,
        })
        .eq("id", spaceId)
    )
  );

  return building.id;
}

export async function updateBuildingSpaceTransform(
  _buildingId: string,
  spaceId: string,
  transform: RigidTransform
): Promise<void> {
  const { error } = await supabase
    .from("spaces")
    .update({ offset_transformation: transform })
    .eq("id", spaceId);
  if (error) throw error;
}

export async function finalizeDraftBuilding(buildingId: string): Promise<void> {
  const { error } = await supabase
    .from("buildings")
    .update({ draft: false })
    .eq("id", buildingId);
  if (error) throw error;
}

export async function saveNavMesh(
  buildingId: string,
  data: Uint8Array,
  glbData: ArrayBuffer,
  buildSettings: Record<string, unknown>
): Promise<void> {
  const binPath = `navmeshes/${buildingId}.bin`;
  const glbPath = `navmeshes/${buildingId}.glb`;

  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: userData } = await supabase
    .from("users")
    .select("site_id")
    .eq("id", user?.id ?? "")
    .single();
  console.log("saveNavMesh:", {
    binPath,
    glbPath,
    bucket: "spaces_bucket",
    binSizeBytes: data.byteLength,
    glbSizeBytes: glbData.byteLength,
    userId: user?.id ?? null,
    userSiteId: userData?.site_id ?? null,
  });

  const { data: building, error: buildingError } = await supabase
    .from("buildings")
    .select("navmesh_id")
    .eq("id", buildingId)
    .single();
  if (buildingError) throw buildingError;

  if (building.navmesh_id) {
    const { error } = await supabase
      .from("navmeshes")
      .update({
        navmesh_path: binPath,
        glb_path: glbPath,
        build_settings: buildSettings,
        updated_at: new Date().toISOString(),
      })
      .eq("id", building.navmesh_id);
    if (error) throw error;
  } else {
    const navmeshId = crypto.randomUUID();
    const { error: insertError } = await supabase
      .from("navmeshes")
      .insert({
        id: navmeshId,
        navmesh_path: binPath,
        glb_path: glbPath,
        build_settings: buildSettings,
      });
    if (insertError) throw insertError;

    const { error: updateError } = await supabase
      .from("buildings")
      .update({ navmesh_id: navmeshId })
      .eq("id", buildingId);
    if (updateError) throw updateError;
  }

  const { error: binUploadError } = await supabase.storage
    .from("spaces_bucket")
    .upload(binPath, data, {
      upsert: true,
      contentType: "application/octet-stream",
    });
  if (binUploadError) {
    console.error(
      "saveNavMesh bin upload error:",
      JSON.stringify(binUploadError, null, 2)
    );
    throw binUploadError;
  }

  const { error: glbUploadError } = await supabase.storage
    .from("spaces_bucket")
    .upload(glbPath, glbData, {
      upsert: true,
      contentType: "model/gltf-binary",
    });
  if (glbUploadError) {
    console.error(
      "saveNavMesh glb upload error:",
      JSON.stringify(glbUploadError, null, 2)
    );
    throw glbUploadError;
  }
}

export async function resetBuildingForRestitch(
  buildingId: string,
  name: string,
  orderedSpaceIds: string[]
): Promise<void> {
  const { error: clearErr } = await supabase
    .from("spaces")
    .update({
      building_id: null,
      building_index: null,
      offset_transformation: null,
    })
    .eq("building_id", buildingId);
  if (clearErr) throw clearErr;

  const { error: buildingErr } = await supabase
    .from("buildings")
    .update({ draft: true, name })
    .eq("id", buildingId);
  if (buildingErr) throw buildingErr;

  await Promise.all(
    orderedSpaceIds.map((spaceId, index) =>
      supabase
        .from("spaces")
        .update({
          building_id: buildingId,
          building_index: index,
          offset_transformation: null,
        })
        .eq("id", spaceId)
    )
  );
}

export async function saveLocBoundingBox(
  spaceId: string,
  bb: import('./types').BoundingBox | null
): Promise<void> {
  const { error } = await supabase
    .from('spaces')
    .update({ loc_bounding_box: bb })
    .eq('id', spaceId);
  if (error) throw error;
}

export async function deleteBuilding(buildingId: string): Promise<void> {
  const { error } = await supabase
    .from("buildings")
    .delete()
    .eq("id", buildingId);
  if (error) throw error;
}

export async function fetchAssetsWithAnchors(
  buildingId: string
): Promise<AssetWithAnchor[]> {
  const { data, error } = await supabase
    .from("assets")
    .select("*, anchor:anchors(*)")
    .eq("building_id", buildingId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data as AssetWithAnchor[];
}

export async function createAsset(params: {
  name: string;
  assetType: string;
  buildingId: string;
}): Promise<Asset> {
  const { data, error } = await supabase
    .from("assets")
    .insert({
      name: params.name,
      asset_type: params.assetType,
      building_id: params.buildingId,
    })
    .select()
    .single();
  if (error) throw error;
  return data as Asset;
}

export async function deleteAsset(id: string): Promise<void> {
  const { error } = await supabase.from("assets").delete().eq("id", id);
  if (error) throw error;
}

export async function setAssetAnchor(
  assetId: string,
  anchorId: string
): Promise<void> {
  const { error } = await supabase
    .from("assets")
    .update({ anchor_id: anchorId })
    .eq("id", assetId);
  if (error) throw error;
}

export function subscribeUserPosition(
  userId: string,
  onChange: (pos: Position | null) => void
): () => void {
  const channel = supabase
    .channel(`user-pos-${userId}`)
    .on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "users",
        filter: `id=eq.${userId}`,
      },
      (payload) =>
        onChange(
          (payload.new as { glb_position?: Position }).glb_position ?? null
        )
    )
    .subscribe();
  return () => supabase.removeChannel(channel);
}
