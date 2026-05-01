import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { GLTFExporter } from "three/examples/jsm/exporters/GLTFExporter.js";
import * as THREE from "three";
import type { RigidTransform } from "./types";

export async function downloadMergedGlb(
  spaces: Array<{ glbUrl: string; transform: RigidTransform | null }>,
  name: string,
): Promise<void> {
  const loader = new GLTFLoader();
  const root = new THREE.Group();

  for (const entry of spaces) {
    const gltf = await new Promise<any>((resolve, reject) =>
      loader.load(entry.glbUrl, resolve, undefined, reject),
    );
    const scene = gltf.scene as THREE.Group;
    if (entry.transform) {
      const { position: p, quaternion: q } = entry.transform;
      scene.position.set(p.x, p.y, p.z);
      scene.quaternion.set(q.x, q.y, q.z, q.w);
    }
    root.add(scene);
  }

  const exporter = new GLTFExporter();
  const buffer = await new Promise<ArrayBuffer>((resolve, reject) =>
    exporter.parse(root, resolve as any, reject, { binary: true }),
  );
  const blob = new Blob([buffer], { type: "model/gltf-binary" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${name || "building"}.glb`;
  a.click();
  URL.revokeObjectURL(url);
}
