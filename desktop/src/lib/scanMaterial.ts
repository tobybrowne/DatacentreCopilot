import * as THREE from 'three'

// Fixed "sharpness" of the scan shading: a multiplier on the key + rim lighting
// (0 = flat hemisphere ambient, higher = crisper, higher-contrast facets).
const SHARPNESS = 0.8

// Faithful port of the headset "dollhouse" hologram shader
// (app/scripts/DollhouseMapManager.gd `_SCAN_SHADER`).
//
// Procedural, orientation-based shading that intentionally ignores the GLB's
// textures: a per-fragment geometric normal is derived from screen-space
// derivatives of world position (so it works even when the decimated scans ship
// without normals, and large triangles flat-shade into clean facets), then shaded
// against a hemisphere ambient (sky tone up / ground tone down), an above-front
// key light, and a fresnel rim for edge definition.

const VERTEX = /* glsl */ `
  varying vec3 vWorldPos;
  void main() {
    vec4 wp = modelMatrix * vec4(position, 1.0);
    vWorldPos = wp.xyz;
    gl_Position = projectionMatrix * viewMatrix * wp;
  }
`

const FRAGMENT = /* glsl */ `
  precision highp float;
  varying vec3 vWorldPos;

  uniform vec3 skyColor;
  uniform vec3 groundColor;
  uniform vec3 keyColor;
  uniform vec3 rimColor;
  uniform float keyStrength;
  uniform float rimStrength;
  uniform float sharpness;         // scales the key + rim lighting
  uniform float normalSign;        // flip to -1.0 if facets/floors look inverted
  uniform vec3 highlightColor;
  uniform float highlightStrength; // optional flat tint (e.g. best-reference space)

  void main() {
    // Geometric normal in world space, straight from position derivatives.
    vec3 nw = normalize(cross(dFdx(vWorldPos), dFdy(vWorldPos))) * normalSign;

    // Hemisphere ambient by surface orientation: floors catch the sky tone,
    // ceilings fall into the ground tone, walls land in between.
    float h = nw.y * 0.5 + 0.5;
    vec3 col = mix(groundColor, skyColor, h);

    // Key light from above-front.
    vec3 keyDir = normalize(vec3(0.3, 0.9, 0.35));
    col += keyColor * (clamp(dot(nw, keyDir), 0.0, 1.0) * keyStrength * sharpness);

    // Fresnel rim for edge definition.
    vec3 viewDir = normalize(cameraPosition - vWorldPos);
    float fres = pow(1.0 - clamp(dot(nw, viewDir), 0.0, 1.0), 3.0);
    col += rimColor * (fres * rimStrength * sharpness);

    // Optional flat highlight tint.
    col += highlightColor * highlightStrength;

    gl_FragColor = vec4(col, 1.0);
  }
`

export interface ScanMaterialOptions {
  skyColor?: THREE.ColorRepresentation
  groundColor?: THREE.ColorRepresentation
  keyColor?: THREE.ColorRepresentation
  rimColor?: THREE.ColorRepresentation
  keyStrength?: number
  rimStrength?: number
  /** Negate the derived normal if floors/ceilings or the rim come out inverted. */
  normalSign?: number
}

export function createScanMaterial(opts: ScanMaterialOptions = {}): THREE.ShaderMaterial {
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERTEX,
    fragmentShader: FRAGMENT,
    // Godot's cull_back is its default cull mode (cull back faces) == Three's
    // default FrontSide, so the near-wall reveal driven by the scan winding looks
    // the same here and editor click/raycast picking is unchanged.
    side: THREE.FrontSide,
    uniforms: {
      // Defaults mirror the Godot uniforms (sky 0.55,0.82,1.0 etc).
      skyColor: { value: new THREE.Color(0.55, 0.82, 1.0) },
      groundColor: { value: new THREE.Color(0.06, 0.10, 0.18) },
      keyColor: { value: new THREE.Color(1.0, 0.96, 0.88) },
      rimColor: { value: new THREE.Color(0.3, 0.55, 0.8) },
      keyStrength: { value: opts.keyStrength ?? 0.55 },
      rimStrength: { value: opts.rimStrength ?? 0.5 },
      sharpness: { value: SHARPNESS },
      normalSign: { value: opts.normalSign ?? 1.0 },
      highlightColor: { value: new THREE.Color(1.0, 0.53, 0.0) },
      highlightStrength: { value: 0.0 },
    },
  })
  if (opts.skyColor !== undefined) mat.uniforms.skyColor.value = new THREE.Color(opts.skyColor)
  if (opts.groundColor !== undefined) mat.uniforms.groundColor.value = new THREE.Color(opts.groundColor)
  if (opts.keyColor !== undefined) mat.uniforms.keyColor.value = new THREE.Color(opts.keyColor)
  if (opts.rimColor !== undefined) mat.uniforms.rimColor.value = new THREE.Color(opts.rimColor)
  // WebGL1 needs the derivatives extension for dFdx/dFdy; ignored on WebGL2.
  mat.extensions = { ...(mat.extensions ?? {}), derivatives: true } as THREE.ShaderMaterial['extensions']
  return mat
}

// Overrides every mesh material under `root` with the procedural scan material.
// Returns true if it touched at least one mesh (used to detect when an async GLTF
// has finished loading). Idempotent: meshes already using `material` are skipped.
export function applyScanMaterial(root: THREE.Object3D, material: THREE.ShaderMaterial): boolean {
  let applied = false
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh
    if (!mesh.isMesh) return
    if (mesh.material === material) return
    mesh.material = material
    mesh.castShadow = false
    mesh.receiveShadow = false
    applied = true
  })
  return applied
}
