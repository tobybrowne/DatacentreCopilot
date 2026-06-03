import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import * as THREE from "three";
import type { RigidTransform } from "./types";

// Renders one or more GLBs (with optional rigid transforms) to static PNG data
// URLs for use in tile previews. A single offscreen WebGLRenderer is shared
// across every thumbnail so a grid of "lots of tiles" never exhausts the
// browser's WebGL context budget — each tile ends up as a plain <img>.
//
// renderGlbThumbnail() returns one framed still; renderGlbFrames() returns a
// turntable (N yaw angles around the model) for the hover-spin effect.

export interface ThumbnailPart {
  url: string;
  transform?: RigidTransform | null;
}

const WIDTH = 512;
const HEIGHT = 384;
// Angle of the default still + the first turntable frame (raised 3/4 view).
const BASE_AZIMUTH = Math.PI / 4;
const ELEVATION = 0.8;

const cache = new Map<string, string>();
const inflight = new Map<string, Promise<string>>();
const framesCache = new Map<string, string[]>();
const framesInflight = new Map<string, Promise<string[]>>();
const loader = new GLTFLoader();

let renderer: THREE.WebGLRenderer | null = null;

function getRenderer(): THREE.WebGLRenderer {
  if (!renderer) {
    renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      preserveDrawingBuffer: true,
    });
    renderer.setSize(WIDTH, HEIGHT, false);
    renderer.setClearColor(0x000000, 0);
  }
  return renderer;
}

// Serialize renders so we only hold one GLB in GPU memory at a time.
let queue: Promise<unknown> = Promise.resolve();

function disposeGroup(group: THREE.Object3D): void {
  group.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (mesh.geometry) mesh.geometry.dispose();
    const mat = mesh.material;
    if (Array.isArray(mat)) mat.forEach(disposeMaterial);
    else if (mat) disposeMaterial(mat);
  });
}

function disposeMaterial(material: THREE.Material): void {
  for (const value of Object.values(material)) {
    if (value instanceof THREE.Texture) value.dispose();
  }
  material.dispose();
}

interface BuiltScene {
  scene: THREE.Scene;
  root: THREE.Group;
  center: THREE.Vector3;
  maxDim: number;
}

async function buildScene(parts: ThumbnailPart[]): Promise<BuiltScene> {
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xffffff, 0.7));
  scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 0.6));
  const dir = new THREE.DirectionalLight(0xffffff, 1.0);
  dir.position.set(5, 10, 7);
  scene.add(dir);

  const root = new THREE.Group();
  for (const part of parts) {
    const gltf = await new Promise<any>((resolve, reject) =>
      loader.load(part.url, resolve, undefined, reject),
    );
    const obj = gltf.scene as THREE.Group;
    if (part.transform) {
      const { position: p, quaternion: q } = part.transform;
      obj.position.set(p.x, p.y, p.z);
      obj.quaternion.set(q.x, q.y, q.z, q.w);
    }
    root.add(obj);
  }
  scene.add(root);

  const box = new THREE.Box3().setFromObject(root);
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const maxDim = Math.max(size.x, size.y, size.z) || 1;
  return { scene, root, center, maxDim };
}

// Render the scene from a given yaw angle and return a PNG data URL.
function renderView(built: BuiltScene, azimuth: number): string {
  const r = getRenderer();
  const camera = new THREE.PerspectiveCamera(50, WIDTH / HEIGHT, 0.01, 1000);
  const dist =
    (built.maxDim / (2 * Math.tan((camera.fov * Math.PI) / 360))) * 1.5;
  const offset = new THREE.Vector3(
    Math.sin(azimuth),
    ELEVATION,
    Math.cos(azimuth),
  )
    .normalize()
    .multiplyScalar(dist);
  camera.position.copy(built.center).add(offset);
  camera.lookAt(built.center);
  camera.updateProjectionMatrix();
  r.render(built.scene, camera);
  return r.domElement.toDataURL("image/png");
}

/**
 * Returns a PNG data URL previewing the given GLB part(s) from a raised 3/4
 * angle. Results are cached by `key`, and concurrent requests for the same key
 * share one render. Renders run one at a time to keep GPU memory bounded.
 */
export function renderGlbThumbnail(
  key: string,
  parts: ThumbnailPart[],
): Promise<string> {
  const cached = cache.get(key);
  if (cached) return Promise.resolve(cached);

  const existing = inflight.get(key);
  if (existing) return existing;

  const task = queue
    .catch(() => {})
    .then(async () => {
      const built = await buildScene(parts);
      const url = renderView(built, BASE_AZIMUTH);
      disposeGroup(built.root);
      return url;
    })
    .then((url) => {
      cache.set(key, url);
      inflight.delete(key);
      return url;
    })
    .catch((err) => {
      inflight.delete(key);
      throw err;
    });

  queue = task.catch(() => {});
  inflight.set(key, task);
  return task;
}

/**
 * Returns `count` PNG data URLs forming a turntable (full 360° yaw) around the
 * model, starting at the same angle as the still thumbnail. Used for the
 * hover-spin effect. Loads the GLB once and renders each angle. Cached by key.
 */
export function renderGlbFrames(
  key: string,
  parts: ThumbnailPart[],
  count = 24,
): Promise<string[]> {
  const cached = framesCache.get(key);
  if (cached) return Promise.resolve(cached);

  const existing = framesInflight.get(key);
  if (existing) return existing;

  const task = queue
    .catch(() => {})
    .then(async () => {
      const built = await buildScene(parts);
      const frames: string[] = [];
      for (let i = 0; i < count; i++) {
        frames.push(
          renderView(built, BASE_AZIMUTH + (i / count) * Math.PI * 2),
        );
      }
      disposeGroup(built.root);
      return frames;
    })
    .then((frames) => {
      framesCache.set(key, frames);
      framesInflight.delete(key);
      // Seed the still cache with frame 0 so the static <img> matches.
      if (!cache.has(key)) cache.set(key, frames[0]);
      return frames;
    })
    .catch((err) => {
      framesInflight.delete(key);
      throw err;
    });

  queue = task.catch(() => {});
  framesInflight.set(key, task);
  return task;
}
