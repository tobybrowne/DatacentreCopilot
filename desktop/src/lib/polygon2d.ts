import type { BoundingBox, RigidTransform } from "./types";

export function extractYaw(t: RigidTransform): number {
  const q = t.quaternion;
  return Math.atan2(
    2 * (q.w * q.y + q.x * q.z),
    1 - 2 * (q.y * q.y + q.z * q.z),
  );
}

function transformPoly(
  bb: BoundingBox,
  tx: number,
  tz: number,
  yaw: number,
): [number, number][] {
  const cos = Math.cos(yaw),
    sin = Math.sin(yaw);
  // Three.js Y-rotation: +X rotates toward -Z, so x' = cos*x + sin*z, z' = -sin*x + cos*z
  return bb.vertices_2d.map(([x, z]) => [
    cos * x + sin * z + tx,
    -sin * x + cos * z + tz,
  ]);
}

function convexHull(pts: [number, number][]): [number, number][] {
  const s = [...pts].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const cross = (
    o: [number, number],
    a: [number, number],
    b: [number, number],
  ) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower: [number, number][] = [];
  for (const p of s) {
    while (
      lower.length >= 2 &&
      cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0
    )
      lower.pop();
    lower.push(p);
  }
  const upper: [number, number][] = [];
  for (const p of [...s].reverse()) {
    while (
      upper.length >= 2 &&
      cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0
    )
      upper.pop();
    upper.push(p);
  }
  lower.pop();
  upper.pop();
  return [...lower, ...upper]; // CCW order
}

function inside(
  p: [number, number],
  a: [number, number],
  b: [number, number],
): boolean {
  return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0;
}

function intersect(
  a: [number, number],
  b: [number, number],
  c: [number, number],
  d: [number, number],
): [number, number] {
  const [ax, ay] = a,
    [bx, by] = b,
    [cx, cy] = c,
    [dx, dy] = d;
  const t =
    ((ax - cx) * (cy - dy) - (ay - cy) * (cx - dx)) /
    ((ax - bx) * (cy - dy) - (ay - by) * (cx - dx));
  return [ax + t * (bx - ax), ay + t * (by - ay)];
}

function clipPolygon(
  subject: [number, number][],
  clip: [number, number][],
): [number, number][] {
  let out = subject;
  const n = clip.length;
  for (let i = 0; i < n && out.length; i++) {
    const a = clip[i],
      b = clip[(i + 1) % n];
    const inp = out;
    out = [];
    for (let j = 0; j < inp.length; j++) {
      const cur = inp[j],
        prev = inp[(j + inp.length - 1) % inp.length];
      if (inside(cur, a, b)) {
        if (!inside(prev, a, b)) out.push(intersect(prev, cur, a, b));
        out.push(cur);
      } else if (inside(prev, a, b)) {
        out.push(intersect(prev, cur, a, b));
      }
    }
  }
  return out;
}

function polyArea(poly: [number, number][]): number {
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const [x1, y1] = poly[i],
      [x2, y2] = poly[(i + 1) % poly.length];
    s += x1 * y2 - x2 * y1;
  }
  return Math.abs(s) / 2;
}

function signedArea(poly: [number, number][]): number {
  let s = 0;
  for (let i = 0; i < poly.length; i++) {
    const [x1, y1] = poly[i],
      [x2, y2] = poly[(i + 1) % poly.length];
    s += x1 * y2 - x2 * y1;
  }
  return s / 2;
}

export function overlapArea(
  bb1: BoundingBox,
  tx1: number,
  tz1: number,
  yaw1: number,
  bb2: BoundingBox,
  tx2: number,
  tz2: number,
  yaw2: number,
): number {
  const h1 = convexHull(transformPoly(bb1, tx1, tz1, yaw1));
  const h2 = convexHull(transformPoly(bb2, tx2, tz2, yaw2));
  // S-H requires clip to be CCW; Andrew's monotone chain produces CCW
  const intersection = clipPolygon(h1, h2);
  return intersection.length >= 3 ? polyArea(intersection) : 0;
}
