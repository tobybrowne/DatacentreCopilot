import { createClient } from "@supabase/supabase-js";
import type {
  Anchor,
  Asset,
  AssetWithAnchor,
  Building,
  LogWithContext,
  Position,
  Procedure,
  ProcedureRun,
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

export async function computeBoundingBox(spaceId: string): Promise<void> {
  const monoUrl = import.meta.env.VITE_MONO_URL as string;
  const res = await fetch(`${monoUrl}/spaces/compute-bbox`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ space_id: spaceId }),
  });
  if (!res.ok) throw new Error(`compute-bbox failed: ${res.statusText}`);
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

async function _upsertNavmeshRow(
  buildingId: string,
  columnId: "navmesh_id" | "floorplan_id",
  binPath: string,
  glbPath: string,
  buildSettings: Record<string, unknown>
): Promise<void> {
  const { data: building, error: buildingError } = await supabase
    .from("buildings")
    .select(columnId)
    .eq("id", buildingId)
    .single();
  if (buildingError) throw buildingError;

  const existingId = building[columnId] as string | null;
  if (existingId) {
    const { error } = await supabase
      .from("navmeshes")
      .update({
        navmesh_path: binPath,
        glb_path: glbPath,
        build_settings: buildSettings,
        updated_at: new Date().toISOString(),
      })
      .eq("id", existingId);
    if (error) throw error;
  } else {
    const navmeshId = crypto.randomUUID();
    const { error: insertError } = await supabase
      .from("navmeshes")
      .insert({ id: navmeshId, navmesh_path: binPath, glb_path: glbPath, build_settings: buildSettings });
    if (insertError) throw insertError;

    const { error: updateError } = await supabase
      .from("buildings")
      .update({ [columnId]: navmeshId })
      .eq("id", buildingId);
    if (updateError) throw updateError;
  }
}

export async function saveNavMesh(
  buildingId: string,
  data: Uint8Array,
  glbData: ArrayBuffer,
  buildSettings: Record<string, unknown>,
  floorplan?: { data: Uint8Array; glbData: ArrayBuffer; buildSettings: Record<string, unknown> }
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

  await _upsertNavmeshRow(buildingId, "navmesh_id", binPath, glbPath, buildSettings);

  const { error: binUploadError } = await supabase.storage
    .from("spaces_bucket")
    .upload(binPath, data, {
      upsert: true,
      contentType: "application/octet-stream",
    });
  if (binUploadError) {
    console.error("saveNavMesh bin upload error:", JSON.stringify(binUploadError, null, 2));
    throw binUploadError;
  }

  const { error: glbUploadError } = await supabase.storage
    .from("spaces_bucket")
    .upload(glbPath, glbData, {
      upsert: true,
      contentType: "model/gltf-binary",
    });
  if (glbUploadError) {
    console.error("saveNavMesh glb upload error:", JSON.stringify(glbUploadError, null, 2));
    throw glbUploadError;
  }

  if (floorplan) {
    const fpBinPath = `navmeshes/${buildingId}_floorplan.bin`;
    const fpGlbPath = `navmeshes/${buildingId}_floorplan.glb`;

    await _upsertNavmeshRow(buildingId, "floorplan_id", fpBinPath, fpGlbPath, floorplan.buildSettings);

    const { error: fpBinErr } = await supabase.storage
      .from("spaces_bucket")
      .upload(fpBinPath, floorplan.data, { upsert: true, contentType: "application/octet-stream" });
    if (fpBinErr) throw fpBinErr;

    const { error: fpGlbErr } = await supabase.storage
      .from("spaces_bucket")
      .upload(fpGlbPath, floorplan.glbData, { upsert: true, contentType: "model/gltf-binary" });
    if (fpGlbErr) throw fpGlbErr;
  }
}

export async function prepareAddSpace(
  buildingId: string,
  existingCount: number,
  newSpaceIds: string[]
): Promise<void> {
  const { error: buildingErr } = await supabase
    .from('buildings')
    .update({ draft: true })
    .eq('id', buildingId);
  if (buildingErr) throw buildingErr;

  await Promise.all(
    newSpaceIds.map((spaceId, index) =>
      supabase
        .from('spaces')
        .update({
          building_id: buildingId,
          building_index: existingCount + index,
          offset_transformation: null,
        })
        .eq('id', spaceId)
    )
  );
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

export async function uploadSpaceGlb(glbPath: string, data: ArrayBuffer): Promise<void> {
  const { error } = await supabase.storage
    .from('spaces_bucket')
    .upload(glbPath, data, { upsert: true, contentType: 'model/gltf-binary' })
  if (error) throw error
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

export async function fetchLogsForBuilding(
  buildingId: string
): Promise<LogWithContext[]> {
  const { data: procs, error: e1 } = await supabase
    .from("procedures")
    .select("id, title, building_id, steps, log_type")
    .eq("building_id", buildingId);
  if (e1) throw e1;
  if (!procs?.length) return [];

  const procMap = new Map(procs.map((p) => [p.id, p as unknown as Procedure]));
  const procIds = procs.map((p) => p.id);

  const { data: runs, error: e2 } = await supabase
    .from("procedure_runs")
    .select("id, procedure_id, user_id, started_at, completed_at")
    .in("procedure_id", procIds);
  if (e2) throw e2;
  if (!runs?.length) return [];

  const runMap = new Map(runs.map((r) => [r.id, r as unknown as ProcedureRun]));
  const runIds = runs.map((r) => r.id);

  // Batch logs queries to avoid PostgREST URL length limits with large IN clauses
  const BATCH = 50;
  const rawLogs: Record<string, unknown>[] = [];
  for (let i = 0; i < runIds.length; i += BATCH) {
    const { data: batch, error } = await supabase
      .from("logs")
      .select("*")
      .in("procedure_run_id", runIds.slice(i, i + BATCH));
    if (error) throw error;
    if (batch) rawLogs.push(...(batch as Record<string, unknown>[]));
  }

  rawLogs.sort((a, b) =>
    (b.created_at as string).localeCompare(a.created_at as string)
  );

  const uniqueUserIds = [...new Set(rawLogs.map((l) => l.user_id as string))];
  const { data: userRows } = await supabase
    .from("users")
    .select("id, contact_email")
    .in("id", uniqueUserIds);
  const emailMap = new Map(
    (userRows ?? []).map((u: { id: string; contact_email: string }) => [u.id, u.contact_email])
  );

  // Fetch log_assets for all logs
  const logIds = rawLogs.map((l) => l.id as string);
  const rawLogAssets: { log_id: string; asset_id: string }[] = [];
  for (let i = 0; i < logIds.length; i += BATCH) {
    const { data: batch, error } = await supabase
      .from("log_assets")
      .select("log_id, asset_id")
      .in("log_id", logIds.slice(i, i + BATCH));
    if (error) throw error;
    if (batch) rawLogAssets.push(...(batch as { log_id: string; asset_id: string }[]));
  }

  const uniqueAssetIds = [...new Set(rawLogAssets.map((la) => la.asset_id))];
  const assetNameMap = new Map<string, string | null>();
  for (let i = 0; i < uniqueAssetIds.length; i += BATCH) {
    const { data: assetBatch } = await supabase
      .from("assets")
      .select("id, name")
      .in("id", uniqueAssetIds.slice(i, i + BATCH));
    (assetBatch ?? []).forEach((a: { id: string; name: string | null }) => assetNameMap.set(a.id, a.name));
  }

  const logAssetsMap = new Map<string, { id: string; name: string | null }[]>();
  for (const la of rawLogAssets) {
    if (!logAssetsMap.has(la.log_id)) logAssetsMap.set(la.log_id, []);
    logAssetsMap.get(la.log_id)!.push({ id: la.asset_id, name: assetNameMap.get(la.asset_id) ?? null });
  }

  return rawLogs.map((log) => {
    const run = log.procedure_run_id
      ? runMap.get(log.procedure_run_id as string)
      : undefined;
    const proc = run ? procMap.get(run.procedure_id) : undefined;
    return {
      ...log,
      userEmail: emailMap.get(log.user_id as string) ?? null,
      assets: logAssetsMap.get(log.id as string) ?? [],
      procedureRun: run && proc ? { ...run, procedure: proc } : null,
    } as LogWithContext;
  });
}

export async function fetchLogById(id: string): Promise<LogWithContext | null> {
  const { data: log, error: e1 } = await supabase
    .from("logs")
    .select("*")
    .eq("id", id)
    .single();
  if (e1) throw e1;
  if (!log) return null;

  const [logAssetsResult, userResult] = await Promise.all([
    supabase.from("log_assets").select("asset_id, assets(id, name)").eq("log_id", log.id),
    supabase.from("users").select("contact_email").eq("id", log.user_id).single(),
  ]);
  const assets = (logAssetsResult.data ?? []).map(
    (la: { asset_id: string; assets: { id: string; name: string | null }[] | { id: string; name: string | null } | null }) => ({
      id: la.asset_id,
      name: Array.isArray(la.assets) ? (la.assets[0]?.name ?? null) : (la.assets?.name ?? null),
    })
  );

  if (!log.procedure_run_id) {
    return { ...log, procedureRun: null, userEmail: userResult.data?.contact_email ?? null, assets } as LogWithContext;
  }

  const { data: run, error: e2 } = await supabase
    .from("procedure_runs")
    .select("id, procedure_id, user_id, started_at, completed_at")
    .eq("id", log.procedure_run_id)
    .single();
  if (e2 || !run) {
    return { ...log, procedureRun: null, userEmail: userResult.data?.contact_email ?? null, assets } as LogWithContext;
  }

  const { data: proc, error: e3 } = await supabase
    .from("procedures")
    .select("id, title, building_id, steps, log_type")
    .eq("id", run.procedure_id)
    .single();
  if (e3 || !proc) {
    return { ...log, procedureRun: null, userEmail: userResult.data?.contact_email ?? null, assets } as LogWithContext;
  }

  return {
    ...log,
    userEmail: userResult.data?.contact_email ?? null,
    assets,
    procedureRun: { ...(run as unknown as ProcedureRun), procedure: proc as unknown as Procedure },
  } as LogWithContext;
}

export async function getLogBucketUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage
    .from("log_bucket")
    .createSignedUrl(path, 3600);
  if (error) throw error;
  return data.signedUrl;
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
