import { useThrelte } from "@threlte/core";
import * as THREE from "three";

/**
 * Returns a `snapshot()` function that renders the current Threlte view to a PNG
 * blob at `scale`× the canvas resolution, then restores the renderer/camera.
 *
 * - `scale()` is read at capture time (so it can follow a reactive prop).
 * - `prepare()` runs just before the render and returns a cleanup that runs
 *   right after (e.g. hide the origin marker, or null the scene background).
 *
 * Must be called during component init (it uses the Threlte context).
 */
export function useSnapshot(opts: {
  onblob?: (blob: Blob) => void;
  scale?: () => number;
  prepare?: () => (() => void) | void;
}): () => void {
  const { renderer, camera, scene, invalidate } = useThrelte();

  return function snapshot(): void {
    invalidate();
    requestAnimationFrame(() => {
      const vp = renderer.getSize(new THREE.Vector2());
      const scale = opts.scale?.() ?? 1;
      const w = vp.x * scale;
      const h = vp.y * scale;

      renderer.setSize(w, h, false);
      const cam = camera.current;
      if (cam instanceof THREE.PerspectiveCamera) {
        cam.aspect = w / h;
        cam.updateProjectionMatrix();
      }

      const restore = opts.prepare?.();
      renderer.render(scene, cam!);

      renderer.domElement.toBlob((blob) => {
        restore?.();
        if (blob) opts.onblob?.(blob);
        renderer.setSize(vp.x, vp.y, false);
        if (cam instanceof THREE.PerspectiveCamera) {
          cam.aspect = vp.x / vp.y;
          cam.updateProjectionMatrix();
        }
        invalidate();
      });
    });
  };
}
