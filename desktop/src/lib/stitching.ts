import type { Position } from './types'

export interface RigidTransform {
  position: Position
  quaternion: { x: number; y: number; z: number; w: number }
}

type V3 = [number, number, number]
type M3 = [V3, V3, V3]  // row-major: M3[row][col]

function sub(a: V3, b: V3): V3 { return [a[0]-b[0], a[1]-b[1], a[2]-b[2]] }
function cross(a: V3, b: V3): V3 {
  return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
}
function normalize(v: V3): V3 {
  const len = Math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
  return len < 1e-10 ? [1, 0, 0] : [v[0]/len, v[1]/len, v[2]/len]
}
function mulMV(M: M3, v: V3): V3 {
  return [
    M[0][0]*v[0] + M[0][1]*v[1] + M[0][2]*v[2],
    M[1][0]*v[0] + M[1][1]*v[1] + M[1][2]*v[2],
    M[2][0]*v[0] + M[2][1]*v[1] + M[2][2]*v[2],
  ]
}
function transposeM(A: M3): M3 {
  return [
    [A[0][0], A[1][0], A[2][0]],
    [A[0][1], A[1][1], A[2][1]],
    [A[0][2], A[1][2], A[2][2]],
  ]
}
function mulMM(A: M3, B: M3): M3 {
  const C: M3 = [[0,0,0],[0,0,0],[0,0,0]]
  for (let i = 0; i < 3; i++)
    for (let j = 0; j < 3; j++)
      for (let k = 0; k < 3; k++)
        C[i][j] += A[i][k] * B[k][j]
  return C
}

// Build orthonormal frame from 3 points.
// Returned matrix has the basis vectors as ROWS (so it can be used in mulMV directly).
function buildFrame(p1: V3, p2: V3, p3: V3): M3 {
  const ex = normalize(sub(p2, p1))
  const ez = normalize(cross(sub(p2, p1), sub(p3, p1)))
  const ey = cross(ez, ex)
  return [ex, ey, ez]  // rows
}

function rotToQuat(R: M3): { x: number; y: number; z: number; w: number } {
  const trace = R[0][0] + R[1][1] + R[2][2]
  let w: number, x: number, y: number, z: number
  if (trace > 0) {
    const s = 0.5 / Math.sqrt(trace + 1)
    w = 0.25 / s
    x = (R[2][1] - R[1][2]) * s
    y = (R[0][2] - R[2][0]) * s
    z = (R[1][0] - R[0][1]) * s
  } else if (R[0][0] > R[1][1] && R[0][0] > R[2][2]) {
    const s = 2 * Math.sqrt(1 + R[0][0] - R[1][1] - R[2][2])
    w = (R[2][1] - R[1][2]) / s; x = 0.25 * s
    y = (R[0][1] + R[1][0]) / s; z = (R[0][2] + R[2][0]) / s
  } else if (R[1][1] > R[2][2]) {
    const s = 2 * Math.sqrt(1 + R[1][1] - R[0][0] - R[2][2])
    w = (R[0][2] - R[2][0]) / s; x = (R[0][1] + R[1][0]) / s
    y = 0.25 * s; z = (R[1][2] + R[2][1]) / s
  } else {
    const s = 2 * Math.sqrt(1 + R[2][2] - R[0][0] - R[1][1])
    w = (R[1][0] - R[0][1]) / s; x = (R[0][2] + R[2][0]) / s
    y = (R[1][2] + R[2][1]) / s; z = 0.25 * s
  }
  return { x, y, z, w }
}

/**
 * Given exactly 3 point correspondences, compute the rigid transform T such that
 * T(src_i) ≈ tgt_i.  Solves exactly via orthonormal frame alignment.
 *
 * @param src  3 points in source mesh local space
 * @param tgt  3 corresponding points in target (reference) mesh local space
 */
export function computeTransform(src: V3[], tgt: V3[]): RigidTransform {
  const Fs = buildFrame(src[0], src[1], src[2])  // source frame (rows = basis vectors)
  const Ft = buildFrame(tgt[0], tgt[1], tgt[2])  // target frame

  // R = Ft^T * Fs  →  maps source frame axes to target frame axes
  // Rows of Fs/Ft are the basis vectors; columns of Fs^T are those vectors.
  // We need R * Fs^T = Ft^T  →  R = Ft^T * Fs
  const R = mulMM(transposeM(Ft), Fs)

  // t = tgt[0] - R * src[0]
  const Rsrc0 = mulMV(R, src[0])
  const t: V3 = [tgt[0][0]-Rsrc0[0], tgt[0][1]-Rsrc0[1], tgt[0][2]-Rsrc0[2]]

  return {
    position: { x: t[0], y: t[1], z: t[2] },
    quaternion: rotToQuat(R),
  }
}

export function posToV3(p: Position): V3 {
  return [p.x, p.y, p.z]
}
