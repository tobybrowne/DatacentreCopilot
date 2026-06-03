import {
  fetchBuildingById,
  getSpaceGlbUrl,
  getNavMeshUrl,
  supabase,
} from "$lib/supabase";
import type { PageLoad } from "./$types";
import type { RigidTransform } from "$lib/types";

export const load: PageLoad = async ({ params }) => {
  const building = await fetchBuildingById(params.id);

  const spaceEntries = await Promise.all(
    [...building.spaces]
      .filter((s) => s.glb_path)
      .sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
      .map(async (s) => ({
        id: s.id,
        url: await getSpaceGlbUrl(s.glb_path!),
        transform: s.offset_transformation as RigidTransform | null,
        boundingBox: s.bounding_box ?? null,
        tightBoundingBox: s.tight_bounding_box ?? null,
      })),
  );

  let existingNavMesh: {
    url: string;
    buildSettings: Record<string, unknown>;
  } | null = null;
  if ((building as any).navmesh_id) {
    const { data: nm } = await supabase
      .from("navmeshes")
      .select("navmesh_path, build_settings")
      .eq("id", (building as any).navmesh_id)
      .single();
    if (nm?.navmesh_path) {
      existingNavMesh = {
        url: await getNavMeshUrl(nm.navmesh_path),
        buildSettings: nm.build_settings ?? {},
      };
    }
  }

  let existingFloorplanNavMesh: {
    url: string;
    buildSettings: Record<string, unknown>;
  } | null = null;
  if ((building as any).floorplan_id) {
    const { data: fp } = await supabase
      .from("navmeshes")
      .select("navmesh_path, build_settings")
      .eq("id", (building as any).floorplan_id)
      .single();
    if (fp?.navmesh_path) {
      existingFloorplanNavMesh = {
        url: await getNavMeshUrl(fp.navmesh_path),
        buildSettings: fp.build_settings ?? {},
      };
    }
  }

  return {
    buildingId: params.id,
    buildingName: building.name ?? "Building",
    spaces: spaceEntries,
    existingNavMesh,
    existingFloorplanNavMesh,
    navmeshId: (building as any).navmesh_id ?? null,
    floorplanId: (building as any).floorplan_id ?? null,
  };
};
