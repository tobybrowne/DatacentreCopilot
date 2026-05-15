import { init as initRecast, importNavMesh, NavMeshQuery } from 'recast-navigation'
import { NavMeshHelper } from '@recast-navigation/three'

async function main() {
  const args = process.argv.slice(2)
  if (args.length < 6) {
    process.stderr.write('Usage: navmesh_query.mjs x1 y1 z1 x2 y2 z2\n')
    process.exit(1)
  }

  const [x1, y1, z1, x2, y2, z2] = args.map(Number)

  const chunks = []
  for await (const chunk of process.stdin) chunks.push(chunk)
  const navmeshData = new Uint8Array(Buffer.concat(chunks))

  await initRecast()

  const { navMesh } = importNavMesh(navmeshData)
  if (!navMesh) {
    process.stderr.write('Failed to import navmesh\n')
    process.exit(1)
  }

  const query = new NavMeshQuery(navMesh)

  function snapToNavMesh(pos) {
    // Tight vertical column first — prefers the polygon directly below/above the anchor.
    const tight = query.findClosestPoint(pos, { halfExtents: { x: 0.3, y: 5.0, z: 0.3 } })
    if (tight.success) return tight
    // Wider search for anchors on walls or in narrow spaces.
    const wide = query.findClosestPoint(pos, { halfExtents: { x: 3.0, y: 5.0, z: 3.0 } })
    if (wide.success) return wide
    // Last resort: very wide sweep for anchors far from walkable surface.
    return query.findClosestPoint(pos, { halfExtents: { x: 8.0, y: 5.0, z: 8.0 } })
  }

  const { point: start, success: startOk } = snapToNavMesh({ x: x1, y: y1, z: z1 })
  const { point: end,   success: endOk   } = snapToNavMesh({ x: x2, y: y2, z: z2 })

  if (!startOk || !endOk) {
    process.stderr.write('Could not snap one or both points to navmesh\n')
    process.exit(1)
  }

  const { path } = query.computePath(start, end)

  // Extract navmesh geometry for rendering
  const helper = new NavMeshHelper(navMesh)
  const geo = helper.mesh.geometry
  const posAttr = geo.attributes.position
  const verts = []
  for (let i = 0; i < posAttr.count; i++) {
    verts.push([posAttr.getX(i), posAttr.getY(i), posAttr.getZ(i)])
  }
  const faces = []
  const idx = geo.index
  if (idx) {
    for (let i = 0; i < idx.count; i += 3) {
      faces.push([idx.getX(i), idx.getX(i + 1), idx.getX(i + 2)])
    }
  }

  process.stdout.write(JSON.stringify({ path, verts, faces, snapStart: start, snapEnd: end }))
}

main().catch(e => {
  process.stderr.write(e.message + '\n')
  process.exit(1)
})
